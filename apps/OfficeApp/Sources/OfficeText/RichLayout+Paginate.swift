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
        // (A float that wraps, set where its anchor puts it, over content
        // set before that anchor on its page: Word leaves the float there
        // and moves that content out from under it — zh-06c46ba9's
        // "分工表格式" box, anchored under a table row parted onto page 70,
        // stands where the row's foot puts its paragraph, and the row's
        // part stands under the box. Found here, such a float is pinned:
        // the pages are set once more with it in place from its page's
        // top (`_pinnedFloats`).)
        var pinnedAnew = false
        var pushedAnew = false
        var bandPushLast = -1, bandPushDelta = 0.0, bandPushPage = -1, bandPushTop = 0.0
        if !pinPass { _columnPushed = _columnPushed.filter { $0 < start } }
        defer {
            if theme.wordRules, !pinPass, pinnedAnew || pushedAnew { _paginate(document, from: start, settled: settled, pinPass: true) }
        }
        var contentH = 1.0
        var page = 0
        var y = 0.0
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
        var deferredTable: String? = nil
        // A table placed against the page further down than the text has
        // come: where the text stood, to go on from there round it.
        var tableReturn: (table: String, y: Double, page: Int, top: Double)? = nil
        // (A table placed against the page that was set up to the page's edge: its table and the edge, in pixels.)
        var pageEdgeClamp: (table: String, edge: Double)? = nil
        var tableBands: [(top: Double, bottom: Double, owner: Int)] = []
        var narrowBands: [(top: Double, bottom: Double, owner: Int, left: Double, right: Double)] = []
        // A page whose columns were balanced at a continuous section break:
        // its physical page and where the next section's columns start.
        var columnFloor: (physical: Int, y: Double)? = nil
        var besideTable: (bottom: Double, page: Int)? = nil
        var reordered = false
        var i = 0
        // A page is as tall as its section's content: the section of the
        // paragraph that opens it.
        var pageFresh = true   // no paragraph has been set on this page yet, not even an empty one
        func openPage() {
            pageFresh = true
            let para = min(i, max(0, count - 1))
            let physical = page / _columns
            if page % _columns == 0 {
                while _pageSection.count <= physical { _pageSection.append(0) }
                _pageSection[physical] = para < _sectionOf.count ? _sectionOf[para] : max(0, _sectionSetups.count - 1)
                _pageHeaderSection[physical] = nil
                // (A page that opens on the empty mark closing a continuous
                // section belongs to the section after it: lo
                // 090716_Studentische_Arbeit_VWS' page 3 opens on such a mark
                // of the second section, whose default header has text, and
                // Word's print gives the page the third section's empty one.)
                if theme.wordRules, physical > 0, i > 0, i < count, i + 1 < _sectionOf.count, i < _cells.count, _cells[i] == nil,
                   case let mark = document.paragraphs[i], mark.text.isEmpty, mark.image == nil, mark.style.sectionXML != nil,
                   mark.style.sectionBreaksPage == false, _sectionOf[i + 1] != _sectionOf[i] {
                    RuleTrace.hit("page-opens-on-a-continuous-section-mark")
                    _pageHeaderSection[physical] = _sectionOf[i + 1]
                }
            }
            // (Between the header and the footer, where they reach past
            // the margins.)
            var insets = _bodyInsets(page: physical, document)
            // (A page a frame goes on to keeps the frame's room inside it
            // again, over the text and under it, as Word parts the frame's
            // one row: zh-045c5a75's law text stands in a wrapper of 0.75pt
            // margins and spacing, and Word sets each page after the first
            // 2.25pt lower than ours and stops 2.25pt higher; ours had
            // that room only where the frame began and ended, took a line
            // more at page 10's foot, and every page after ran a line
            // ahead.)
            if theme.wordRules, page > 0, para < count, case let st = document.paragraphs[para].style,
               st.frameInsetTop > 0 || st.frameInsetBottom > 0,
               _pages[page - 1].contains(where: { $0.paragraph < count && !$0.repeated && document.paragraphs[$0.paragraph].style.frameInsetTop + document.paragraphs[$0.paragraph].style.frameInsetBottom > 0 }) {
                insets.top += _px(st.frameInsetTop)
                insets.bottom += _px(st.frameInsetBottom)
            }
            while _pageInsetTop.count <= physical { _pageInsetTop.append(0) }
            _pageInsetTop[physical] = insets.top
            contentH = max(1, _px(pageSetup(forPage: physical).height) - insets.top - insets.bottom - (_columns > 1 ? _columnNoteReserve[page] ?? 0 : 0))
        }
        // Where the flow stood before a frame placed on the page (see
        // below), and the page it is on.
        var frameReturn: (y: Double, page: Int)? = nil
        // (Where a frame text does not go beside ends on its page: the flow goes on from there.)
        var frameFoot: (y: Double, page: Int, top: Double)? = nil
        var resumeCursor: Double? = nil
        // The previous result, to splice back in once the flow past the
        // change lands where it did before.
        let oldPieces = _allPieces
        let oldPages = _pages
        let oldStart = _pieceStart
        var restarted = false
        // Restart on the page where the first changed paragraph begins,
        // from that page's first piece; the pages before it are kept.
        if start > 0, start < count, _pieceStart.count == count + 1, _pieceStart[start] < _allPieces.count,
           case let p = _allPieces[_pieceStart[start]].page, p > 0, p < _pages.count,
           let first = _pages[p].first(where: { !$0.repeated }), first.part == .all {
            page = p
            i = first.paragraph
            resumeCursor = first.flowTop
            restarted = true
            _pages.removeSubrange(p...)
            _pages.append([])
            _pages[p].reserveCapacity(32)
            if let k = _allPieces.firstIndex(where: { $0.paragraph == i && $0.flowTop >= first.flowTop - 0.01 }) {
                _allPieces.removeSubrange(k...)
            } else {
                _allPieces.removeAll(keepingCapacity: true)
            }
        } else {
            _pages = [[]]
            _pages[0].reserveCapacity(32)
            _allPieces.removeAll(keepingCapacity: true)
        }
        let oldNotes = _pageNotes
        _pageNotes = _pageNotes.filter { $0.key < page }
        let oldCuts = _noteCutOut, oldCarries = _noteCarryIn
        _noteCutOut = _noteCutOut.filter { $0.key < page }
        _noteCarryIn = _noteCarryIn.filter { $0.key < page }
        // (The pins of the pages set again are found again; those of the
        // pages kept stand, and so do their floats' shifts.)
        var shelvedPins: [String: (pin: (page: Int, top: Double, bottom: Double, left: Double, right: Double, anchorY: Double), shift: Double?)] = [:]
        if !pinPass {
            for (id, pin) in _pinnedFloats where pin.page >= page {
                shelvedPins[id] = (pin, _floatShiftY[id])
                _floatShiftY[id] = nil
                _pinnedFloats[id] = nil
            }
        }
        var prevContentH = contentH
        var prevY = 0.0   // how far down the page before was filled
        var prevPartBottom: Double? = nil   // where the part of a row that parted there ends, when a cell runs on below it
        // The floating pictures on this page that text wraps round: page
        // y, and x from the column's edge.
        var bands: [(top: Double, bottom: Double, left: Double, right: Double)] = []
        // The pinned floats' bands on this page (in `bands` too), which a
        // table's rows keep clear of as well.
        var pinBands: [(top: Double, bottom: Double, left: Double, right: Double)] = []
        func loadPins() {
            pinBands = _pinnedFloats.values.filter { $0.page == page }.map { ($0.top, $0.bottom, $0.left, $0.right) }
            bands += pinBands
        }
        // Down past the pinned floats that what is `height` tall would
        // run into here.
        func underPins(_ height: Double) {
            var steps = 0
            while steps < 4, let b = pinBands.first(where: { $0.top < y + height - 0.5 && $0.bottom > y + 0.5 }) {
                y = b.bottom
                steps += 1
            }
        }
        // The paragraphs of nothing but floating pictures set on this
        // page since the last with text (`_anchorsOnly`).
        var anchorRun: [Int] = []
        // A paragraph of no height that ends a section stands on its page:
        // the page is not empty (see the section rule in the loop).
        var markOnPage = false
        // A line on this page hangs past its foot (by its grid's overhang).
        var overfull = false
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
        let slotNotes = theme.wordRules && RichTextTheme.wordWindowsPages && _columns > 1 && !_perSection && !document.footnotes.isEmpty
        _slotNotes = slotNotes
        let notesOn = theme.wordRules && !document.footnotes.isEmpty && (_columns == 1 || slotNotes)
        func noteWidth() -> Double {
            let s = pageSetup(forPage: page / _columns)
            return _px(slotNotes ? s.columnWidth : s.contentWidth)
        }
        var pageNotes: [Int] = []
        var placing: [Int] = []
        var placingRange = 0 ..< 0
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
        func reserveNotes(_ ids: [Int], deferring: Bool = false) {
            guard notesOn else { return }
            let width = noteWidth()
            var deferred = false
            for id in ids where !pageNotes.contains(id) {
                if deferred { if !pendingNotes.contains(id) { pendingNotes.append(id) }; continue }
                guard let note = _note(id, width: width, document) else { continue }
                var room = pageCut?.id == id ? pageCut!.keep : note.height
                if pageNotes.isEmpty { room += _note(-1, width: width, document)?.height ?? 0 }
                if deferring, room > contentH - y + 0.01 {
                    deferred = true
                    if !pendingNotes.contains(id) { pendingNotes.append(id) }
                    continue
                }
                contentH = max(1, contentH - room)
                pageNotes.append(id)
            }
        }
        func newPage() {
            bands.removeAll()
            tableBands.removeAll()
            narrowBands.removeAll()
            anchorRun.removeAll()
            markOnPage = false
            overfull = false
            spacedPast = nil
            var carried: [Int] = []
            var goesOn: Double? = nil   // where the paragraph parted here goes on, in its flow
            if notesOn {
                let stays = _pages[page].contains { placingRange.contains($0.paragraph) && !$0.repeated }
                carried = stays ? [] : placing.filter { pageNotes.contains($0) }
                if !stays { carried += rowPending; rowPending = [] }
                // (A paragraph parted here keeps on this page only the
                // notes whose marks are in its lines here: zh-424775e4's
                // footnote 2, marked in the fourth line of a paragraph
                // that page 9 holds the first three of, stands at page
                // 10's foot in Word's print; ours set it on page 9, and
                // took three more lines over for it.)
                if stays, theme.wordRules, placingRange.count == 1, _cells[placingRange.lowerBound] == nil,
                   let here = _pages[page].last(where: { $0.paragraph == placingRange.lowerBound && !$0.repeated }) {
                    carried = placing.filter { id in
                        pageNotes.contains(id) && (_footnoteMarkTop(placingRange.lowerBound, id, document).map { $0 >= here.flowBottom - 0.01 } ?? false)
                    }
                    goesOn = here.flowBottom
                }
                _pageNotes[page] = pageNotes.filter { !carried.contains($0) }
                if let cut = pageCut, _pageNotes[page]?.contains(cut.id) == true { _noteCutOut[page] = cut } else { pageCut = nil }
                pageNotes = []
                // (The notes still waiting for an unkept paragraph go
                // over too, after those carried, in the file's order.)
                for id in pendingNotes where !carried.contains(id) { carried.append(id) }
                pendingNotes = []
                carried.sort()
            }
            var fresh: [PagePiece] = []
            fresh.reserveCapacity(32)
            if page + 1 < _pages.count { page += 1 } else { _pages.append(fresh); page += 1 }
            // (A section of fewer columns than the most has none past its
            // last: the next page's first.)
            if _perSection, case let here = _columnsOf(paragraph: min(i, max(0, count - 1))), here < _columns {
                while page % _columns >= here {
                    if page + 1 < _pages.count { page += 1 } else { _pages.append([]); page += 1 }
                }
            }
            prevY = y
            y = 0
            // (A column of a page whose columns were balanced at a
            // continuous break starts under the balanced block.)
            if let floor = columnFloor, floor.physical == page / max(1, _columns) { y = floor.y }
            prevContentH = contentH
            openPage()
            loadPins()
            // (The rest of a note the page before parted, first under the
            // rule.)
            if notesOn, let cut = pageCut {
                pageCut = nil
                let width = noteWidth()
                if let note = _note(cut.id, width: width, document) {
                    contentH = max(1, contentH - (note.height - cut.keep) - (_note(-1, width: width, document)?.height ?? 0))
                    pageNotes.append(cut.id)
                    _noteCarryIn[page] = (cut.id, cut.keep)
                }
            }
            // (A paragraph going on here takes on this page those of its
            // notes whose marks stand in the lines this page will hold of
            // it, as where it began — and parts the first that does not
            // fit, a line of it or more fitting under its mark: zh-344a8d08's
            // "(一)因應COVID-19疫情…", begun on page 3, marks footnotes 2
            // and 3 on page 4, where Word's print sets 2 and two lines of
            // 3. Ours reserved both whole at page 4's head, then took 3
            // over with its mark's line and left page 4 its room empty.)
            if notesOn, theme.wordRules, let flow = goesOn {
                let i0 = placingRange.lowerBound
                let mine = (carried + rowPending).filter { placing.contains($0) }.sorted()
                carried.removeAll { mine.contains($0) }
                rowPending = []
                reserveNotes(carried)
                let width = noteWidth()
                var here: [Int] = []
                var room = 0.0
                for (n, id) in mine.enumerated() {
                    guard let mark = _footnoteMarkLine(i0, id, document), let note = _note(id, width: width, document) else { here.append(id); continue }
                    room += note.height + (pageNotes.isEmpty && here.isEmpty ? _note(-1, width: width, document)?.height ?? 0 : 0)
                    let at = y + (mark.bottom - flow)
                    if at + room > contentH + 0.01 {
                        let left = contentH - at - (room - note.height)
                        if pageCut == nil, let keep = _noteCuts(id, width: width, document).last(where: { $0 <= left + 0.01 }) {
                            pageCut = (id, keep)
                            here.append(id)
                            rowPending = Array(mine[(n + 1)...])
                        } else {
                            // (With no line of it fitting under its mark,
                            // the mark's line goes over with it, as where
                            // the paragraph began: the page ends over that
                            // line — less nothing, the room of the notes
                            // taken before it comes off the foot in
                            // `reserveNotes` next. zh-7a16a243's "都市計畫法第
                            // 32條34及第22條35規定…", the last line page 42
                            // holds of a paragraph begun on page 41, marks
                            // notes 34 and 35; Word's print opens page 43
                            // with that line, both notes at its foot. Ours
                            // kept the line with note 34 and set 35 first on
                            // page 43, and pages 43-51 ran a line ahead.)
                            if y > 0.01 || mark.top - flow > 0.5 {
                                contentH = max(1, min(contentH, y + (mark.top - flow) + (here.isEmpty ? 0 : room - note.height)))
                            }
                            rowPending = Array(mine[n...])
                        }
                        break
                    }
                    here.append(id)
                }
                reserveNotes(here)
                return
            }
            reserveNotes(carried)
        }
        loadPins()
        _blankPages = _blankPages.filter { $0 < page / _columns }
        _numberedBlankPages = _numberedBlankPages.filter { $0 < page / _columns }
        if restarted {
            // (The page restarted on keeps its section.)
            let insets = _bodyInsets(page: page / _columns, document)
            contentH = max(1, _px(pageSetup(forPage: page / _columns).height) - insets.top - insets.bottom - (_columns > 1 ? _columnNoteReserve[page] ?? 0 : 0))
        } else {
            _pageSection.removeAll(keepingCapacity: true)
            _pageHeaderSection = [:]
            openPage()
        }
        func add(_ piece: PagePiece) {
            _pages[page].append(piece)
            _allPieces.append(piece)
            pageFresh = false
        }
        // A table's header row, repeated at the top of each later page it
        // runs on: the row's pieces again, marked, in the page only.
        // How many of a table's first rows are its header, repeated on
        // each page it runs on: the rows the file marks — none where it
        // marks them all, which Word repeats nothing of (a form of
        // sixteen rows, each marked: every page began with the form's
        // head again and never got past it).
        func headerRows(_ table: String) -> Int {
            guard let ts = document.tableStyles[table], ts.headerRow else { return 0 }
            let n = theme.wordRules ? max(1, ts.headerRowCount) : 1
            return theme.wordRules && n > (_tableRows[table] ?? 0) ? 0 : n
        }
        var omittedHeadHeight: [String: Double] = [:]
        func repeatHeader(of table: String, before i: Int) {
            // (Nothing where the page breaks inside the header: its rows
            // go on as rows. bug57031's "Test of Equality over Strata",
            // two header rows parted after the first at page 12's foot,
            // opens page 13 with its second once in Word's print, where
            // ours set both again above it: the second twice.)
            if theme.wordRules, let r = _cells[i]?.row, _cells[i]?.table == table, r < headerRows(table) { return }
            var k0 = i
            while k0 > 0, let d = _cells[k0 - 1], d.table == table { k0 -= 1 }
            guard let h = _cells[k0], h.row == 0 else { return }
            // (Nor where the header and the row under it that may not part do
            // not stand on a page together: lo Cool16066_addRowsUnderOmittedHeading's
            // 10 cm header and its 40-line row, whole, make 843pt for 728, and
            // Word's print sets the row at page 2's top with no header over it.)
            if theme.wordRules, let next = _cells[i], next.table == table, next.row >= headerRows(table),
               document.tableStyles[table]?.rowsCantSplit.contains(next.row) == true {
                var head = 0.0
                var n = k0
                while n < count, let d = _cells[n], d.table == table, d.row < headerRows(table) {
                    head = max(head, d.rowTop + d.ownRowHeight - h.rowTop)
                    n += 1
                }
                if head + next.ownRowHeight > contentH + 0.01, next.ownRowHeight <= contentH + 0.01 {
                    omittedHeadHeight[table] = head
                    return
                }
            }
            // (Every row the file marks as a header, where Word's rules
            // are followed: a heading of two rows is repeated whole.)
            let rows = headerRows(table)
            var j = k0
            var height = 0.0
            var pieces: [PagePiece] = []
            // (A header of exact rows whose cells are merged down past it
            // is repeated at its rows' own height, each cell's text set
            // in that again: zh-fec5fa30's forms head with one row of
            // exactly 45.35pt, every cell merged into a row under it that
            // has none of its own, and Word's later pages open with the
            // 45.35 — ours repeated both, 79.35, and every row went down
            // 34pt.)
            // (One of at least its height too, with its rule, and as
            // tall as the text of its cells that end in it needs: pages
            // 31-32's, at least 45.35pt, open with 46.4 in Word's print.)
            var cut: Double? = nil
            if theme.wordRules, let ts = document.tableStyles[table], (0 ..< rows).allSatisfy({ ts.rowHeights[$0] != nil }) {
                var n = k0
                var past = false
                var need = 0.0
                while n < count, let d = _cells[n], d.table == table, d.row < rows {
                    past = past || d.row + d.rowSpan > rows
                    var last = n
                    while last + 1 < count, let e = _cells[last + 1], e.table == table, e.row == d.row, e.column == d.column { last += 1 }
                    // (A cell merged down asks its room of the rows it
                    // ends in, not of the header: pages 31-32's
                    // "評核重點項目", 50pt with its half lines before and
                    // after, stands in Word's 46.4.)
                    if d.row + d.rowSpan <= rows {
                        need = max(need, _tops[last] + _heights[last] - _tops[n] + d.pad.top + d.pad.bottom)
                    }
                    n = last + 1
                }
                let stated = (0 ..< rows).reduce(0.0) {
                    $0 + _px(ts.rowHeights[$1]!) + (ts.rowsExactHeight.contains($1) ? 0 : max(0, h.rules - h.ruleBelow))
                }
                let all = (0 ..< rows).allSatisfy { ts.rowsExactHeight.contains($0) } ? stated : max(stated, need)
                if past, all < h.ownRowHeight - 0.5 { cut = all }
            }
            if let cut {
                var n = k0
                while n < count, let d = _cells[n], d.table == table, d.row < rows {
                    // The cell's paragraphs, and where its text stands in them.
                    var last = n
                    while last + 1 < count, let e = _cells[last + 1], e.table == table, e.row == d.row, e.column == d.column { last += 1 }
                    let text = _tops[last] + _heights[last] - _tops[n]
                    // (Centred over it even where it is taller, as Word
                    // sets "評核重點項目" in 46.4.)
                    let spare = cut - d.pad.top - d.pad.bottom - text
                    let room = d.verticalAlign == "center" ? spare : max(0, spare)
                    let at = d.rowTop + d.pad.top + (d.verticalAlign == "center" ? room / 2 : d.verticalAlign == "bottom" ? room : 0)
                    let up = d.vertical ? 0 : _tops[n] - at
                    let pageY = y + (d.rowTop - h.rowTop)
                    for k in n ... last {
                        var piece = PagePiece(paragraph: k, flowTop: d.rowTop + up, flowBottom: d.rowTop + up + cut, page: page, pageY: pageY)
                        piece.repeated = true
                        piece.part = .text
                        pieces.append(piece)
                    }
                    var rules = PagePiece(paragraph: n, flowTop: d.rowTop, flowBottom: d.rowTop + cut, page: page, pageY: pageY)
                    rules.repeated = true
                    rules.part = .rules
                    rules.inner = true
                    pieces.append(rules)
                    n = last + 1
                }
                j = n
                height = cut
            }
            while cut == nil, j < count, let d = _cells[j], d.table == table, d.row < rows {
                let bottom = d.rowSpan > 1 ? d.rowTop + d.rowHeight : d.rowTop + d.ownRowHeight
                var piece = PagePiece(paragraph: j, flowTop: d.rowTop, flowBottom: bottom, page: page, pageY: y + (d.rowTop - h.rowTop))
                piece.repeated = true
                pieces.append(piece)
                height = max(height, d.rowTop + d.ownRowHeight - h.rowTop)
                j += 1
            }
            // (The line under the header is the room between it and the
            // row it now stands over, whatever that row's own top line:
            // lab `hl` (Word for Mac, zh-e1b09977's calendar): a 2.25pt
            // line under two header rows takes its whole width under
            // them, on the first page and under each repeat alike, and
            // the next row's text stands 13.68 under its foot. Ours gave
            // the row its own half-point top from the row above it in
            // the file, and the repeated pages' rows stood 1.7pt high.)
            if theme.wordRules, let next = _cells[i], next.table == table, next.row >= rows {
                var under = 0.0
                var n = k0
                while n < count, let d = _cells[n], d.table == table, d.row < rows {
                    if d.row + d.rowSpan >= rows, let side = Self._cellSide(document.paragraphs[n].cell?.bordersXML, "bottom") {
                        under = max(under, _px(Self._ruleRoom(side.style, side.width)))
                    }
                    n += 1
                }
                // (Not over a row whose cells state their own top — nil,
                // none, or a line: zh-6e7ff836's repeats stand over rows
                // whose tops say nil, and Word's print gives the header's
                // double line no room more there.)
                var stated = false
                var m = i
                while m < count, let e = _cells[m], e.table == table, e.row == next.row {
                    if document.paragraphs[m].cell?.bordersXML?.containsSubstring("<w:top ") == true { stated = true }
                    m += 1
                }
                let own = max(0, next.rules - next.ruleBelow)
                // (In a table that draws no lines between rows, only the room
                // its first page gave it: tdf170672's header, a 1.5pt line
                // of its cells' own over margins of 5.4pt, stands 80.1pt over
                // its second row on every page of Word's print and of ours on
                // the first — and the repeats, asking the line's room again,
                // 81.5. Tables with lines of their own keep the lab `hl` room:
                // zh-e1b09977, zh-64044a1d.)
                var gap = Double.infinity
                let ruled = document.tableStyles[table].map { $0.edges?.insideH ?? ($0.borders && !$0.bordersFromCells) } ?? true
                if cut == nil, !ruled, let first = (k0 ..< count).first(where: { _cells[$0]?.table == table && _cells[$0]?.row == rows }),
                   let low = _cells[first] {
                    gap = max(0, low.rowTop - (h.rowTop + height))
                }
                if !stated, under > own + 0.01 { height += min(under - own, gap) }
            }
            // (Not a header that leaves the page no room under it.)
            guard height < contentH - y - 1 else { return }
            _pages[page].append(contentsOf: pieces)
            y += height
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
        var linesUnderRows: [String: [Int: Double]] = [:]
        func lineUnderRow(_ c: _CellGeo) -> Double {
            if let rows = linesUnderRows[c.table] { return rows[c.row] ?? 0 }
            var rows: [Int: Double] = [:]
            for d in _cells {
                guard let d, d.table == c.table else { continue }
                rows[d.row + d.rowSpan - 1] = max(rows[d.row + d.rowSpan - 1] ?? 0, d.ruleNext)
            }
            linesUnderRows[c.table] = rows
            return rows[c.row] ?? 0
        }
        func ruleUnder(_ c: _CellGeo, parted: Bool = false, across: Bool = false) -> Double {
            guard theme.wordRules else { return 0 }
            // (A first cell merged down past the row is no measure of the
            // line under it: the cells that end there are. zh-4f70ee2d's
            // p19 row "1 | 党委政府分别组织…" (at least 28.35 under a 1.5pt
            // line, 30.2 left) opens with "党委政府组织领导情况", merged
            // down to the table's last row, whose bottom line it carries;
            // ours took the row for the table's last, asked nothing under
            // it, and parted it, where Word asks the 0.5 line its other
            // cells end on and sends it to page 20 whole.)
            // (Not `across` the rows the merge runs down through, where its
            // text is centred over those that fit: zh-0a56c942's p9
            // "个人学习和工作简历", merged down to the table's last row, is
            // centred over the six rows on that page in Word's print, the
            // last ending 1.48pt over the foot; asking a 1.5 line under
            // each left that row out and set it 22pt high.)
            let spansOn = c.rowSpan > 1 && !across
            // (The line drawn under the row where it ends a page whole:
            // see `ruleNext`. A row with the table's bottom line in its
            // own height asks nothing more; a parted row's piece keeps
            // asking its own top line's width, as before — zh-e061a08e's
            // page 4 parts a row under a thicker line at Word's line.)
            if c.ruleBelow > 0 && !parted && !spansOn { return 0 }
            // (In Word for Windows' 2007 mode, the half of the line that hangs
            // under the row's edge: zh-1a3c7aa0, mode 12, sets page 13's
            // "5 O,O-二甲基…" row under a 0.5pt line with 0.22pt left,
            // where bug65649's 0.75 line with 0.6 left, mode 15, did not,
            // nor zh-d68ac84a's p36 row with 0.53 left, mode 14.)
            if parted {
                let own = max(0, c.rules - c.ruleBelow)
                // (A table framed by outer lines with none between its rows
                // still closes a parted row with its bottom line and opens
                // the next page's part with its top: lo-e1104feb's floating
                // table, 3pt green outside and none inside, has a 3pt rule
                // at p1's foot and p2's head in Word's print, the part 3pt lower.)
                if own == 0, RichTextTheme.wordWindowsPages, let ts = document.tableStyles[c.table],
                   Self._partedFrame(ts) { return _px(Self._ruleRoom(ts.edgeStyles["top"] ?? ts.borderStyle, ts.edgeWidths["top"] ?? ts.borderWidth ?? 0.5)) }
                return own
            }
            // (Where the row ends the page, the table's own bottom line
            // closes it there when that is the heavier: zh-77bd4900's
            // tables, a 0.75pt line between rows and 1.5 round them,
            // close page 18 under a 1.44pt line in Word's print, and its
            // "Ex:第一期費用" row, which fits with the half a point but not
            // with the one and a half, goes to page 19; ours kept it.)
            var bottom = 0.0
            if let ts = document.tableStyles[c.table], ts.edges?.bottom ?? (ts.borders && !ts.bordersFromCells) {
                bottom = _px(Self._ruleRoom(ts.edgeStyles["bottom"] ?? ts.borderStyle, ts.edgeWidths["bottom"] ?? ts.borderWidth ?? 0.5))
            }
            // (Word for Windows closes the page as if the row were the
            // table's last: under the cell's own bottom line where it states
            // one, else the table's — labs t187 and t190: zh-cec9d337's row
            // 四, its cells' own half-point bottoms in a table whose bottom
            // is a 3pt double, stays at page 16's foot with 1.0pt left
            // under the 0.48 line, and with those bottoms taken out goes
            // over under the double; zh-e1b09977's p13, no cell lines of its
            // own, closes under its table's 2.16 bottom.)
            if RichTextTheme.wordWindowsPages, c.edges?.bottom != nil || c.borders.bottom != nil { bottom = 0 }
            // (Word for Mac asks the whole closing line even in mode 12:
            // ordinary and merged two-row controls, with 0.5/1.5pt rules,
            // keep the first row only with the full rule's room. Removing
            // the table's top line or making it heavier leaves that test
            // unchanged. The old half-line allowance admitted zh-90e0cea8's
            // p8 row 29 when its header got 0.033pt shorter, moving the
            // merged label 8pt away from Word.)
            let half = RichTextTheme.wordWindowsPages && (document.compatibilityMode ?? 12) < 14
            // (A heavy line between two rows, as the foot of a page closes on it, takes only its
            // upper half of room there in Word for Windows' print: zh-db07d44e's p7 row
            // "大口徑管線爆管減少率" (22.7 under a 0.5 line, the 1.5 line round the merge's
            // foot under it) is 24.4 from the foot and fits, ours asked 24.7.)
            let line = max(0, spansOn ? lineUnderRow(c) : c.ruleNext)
            if RichTextTheme.wordWindowsPages, !half, line > _px(1), line > bottom + 0.01 { return line / 2 }
            return max(0, spansOn ? lineUnderRow(c) : c.ruleNext, (document.compatibilityMode ?? 12) >= 14 ? bottom : 0) / (half ? 2 : 1)
        }
        // What a row's part at a page's foot is closed with there: its
        // top line's width, as `ruleUnder(parted:)` has it — and in the
        // table's last row, from Word 2010's layout on, the table's bottom
        // line, which Word draws under the part. Lab `ef2b` (Word 16 Mac,
        // mode 14, zh-e1b09977's package): a cell of four 17pt lines over
        // a 2.25pt bottom line parts after its third with 15 to 19pt left
        // under that, and keeps all four from 20; ours, leaving the top
        // line's 0.5, took the fourth for a line that fits, had nothing
        // left to send over, and took the row over whole at 18 and 19.
        // (In any row, not only the last: zh-e1b09977's p14 parts a row in
        // the table's middle, and Word's print closes the part with the
        // table's 2.25pt bottom line, 759.12-761.28 under its last line;
        // ours asked the 0.5 top line and kept a line more.)
        // The extra room a row opening a page the table goes on over
        // takes for the table's top line, where a cell of it states no top
        // line of its own: zh-cec9d337's p19, p25 and p26 — see where a
        // part goes over in `splitRow`.
        func headLift(_ i: Int, _ j: Int, _ c: _CellGeo) -> Double {
            guard theme.wordRules, c.row > 0, let ts = document.tableStyles[c.table],
                  ts.edges?.top ?? (ts.borders && !ts.bordersFromCells),
                  !(RichTextTheme.wordWindowsPages && Self._partedFrame(ts)),
                  (i ..< j).contains(where: { k in
                      document.paragraphs[k].cell.map { d in !(d.bordersXML ?? "").containsSubstring("<w:top ") && d.edges?.top == nil } ?? false
                  }) else { return 0 }
            return max(0, _px(Self._ruleRoom(ts.edgeStyles["top"] ?? ts.borderStyle, ts.edgeWidths["top"] ?? ts.borderWidth ?? 0.5)) - max(0, c.rules - c.ruleBelow))
        }
        func ruleClosing(_ c: _CellGeo) -> Double {
            let own = ruleUnder(c, parted: true)
            guard theme.wordRules, (document.compatibilityMode ?? 12) >= 14 else { return own }
            if c.ruleBelow > 0 { return max(own, c.ruleBelow) }
            // (A cell's own heavy bottom line closes the part too, by its upper half: 9ba34429's row of a tall
            // cell and three one-line ones, 2.25pt bottoms, has 11.34pt at page 2's foot, and its first line,
            // 10.5, goes over with the row in Word, as 10.5 + 1.125 > 11.34.)
            if RichTextTheme.wordWindowsPages, c.edges?.bottom != nil || c.borders.bottom != nil, c.ruleNext > _px(1) { return max(own, c.ruleNext) }
            // (Only a bottom line heavier than the table's inside ones, and
            // only under a cell that states no bottom of its own:
            // zh-cec9d337's cells, half-point lines of their own inside a
            // table whose bottom is a 3pt double, part as they did.)
            guard c.edges?.bottom == nil, let ts = document.tableStyles[c.table],
                  ts.edges?.bottom ?? (ts.borders && !ts.bordersFromCells) else { return own }
            let bottomWidth = ts.edgeWidths["bottom"] ?? ts.borderWidth ?? 0.5
            guard bottomWidth > (ts.edgeWidths["insideH"] ?? ts.borderWidth ?? 0.5) + 0.01 else { return own }
            return max(own, _px(Self._ruleRoom(ts.edgeStyles["bottom"] ?? ts.borderStyle, bottomWidth)))
        }
        // (How far past a part's foot a nested row may begin and still stay, in Word for Windows, where the table
        // holding it is placed against the page: the row lines above it do not count. Labs nt1/nt1b (windows):
        // a 90-row table in the one cell of a page-anchored floating row keeps every row whose top, less the
        // lines stacked above it, is above the margin — one row more than the lines counted, whatever the
        // footer's distance; a plain outer row cuts where the lines are counted. LibreOffice's fdo77887 and
        // fdo48718-1: 44 rows on page 1 in Word's print, 42 in ours. One slack per cut, as `cellCuts` lists them.)
        func cellSlacks(_ k: Int) -> [Double] {
            let n = cellCuts(k).count
            guard theme.wordRules, RichTextTheme.wordWindowsPages, let outer = _cells[k], document.tableStyles[outer.table]?.pageAnchored == true,
                  let image = document.paragraphs[k].image, image.textBox?.growsToFit == true,
                  let inside = _textBox(image, document) else { return Array(repeating: 0, count: n) }
            var heights: [Double: (height: Double, rules: Double)] = [:]
            let first = inside.layout._cells.compactMap({ $0 }).first?.table
            for m in 0 ..< min(inside.document.paragraphs.count, inside.layout._cells.count) {
                if let c = inside.layout._cells[m], c.firstInRow, c.table == first {
                    heights[c.rowTop + c.ownRowHeight] = (c.ownRowHeight, c.rules)
                }
            }
            var slacks: [Double] = [], above = 0.0
            for bottom in heights.keys.sorted() {
                let row = heights[bottom]!
                slacks.append(row.height + above)
                above += row.rules
            }
            slacks.removeLast()
            return slacks + Array(repeating: 0, count: max(0, n - slacks.count))
        }
        func cellCuts(_ k: Int) -> [Double] {
            let g = geometry(k)
            // (A table nested in the cell parts between its rows, as
            // Word's does: zh-d35cbbdb's consent table, its first row
            // "項目 / 土地部分 / 合法建物部分" at page 4's foot in a cell
            // of the page-long layout table, the rest on page 5 — ours
            // took the whole table over.)
            if theme.wordRules, let image = document.paragraphs[k].image, image.textBox?.growsToFit == true,
               let inside = _textBox(image, document) {
                let top = g.textTop + (k < _imageDrop.count ? _imageDrop[k] : 0)
                var rows = Set<Double>()
                for m in 0 ..< min(inside.document.paragraphs.count, inside.layout._cells.count) {
                    if let c = inside.layout._cells[m], c.firstInRow, c.table == inside.layout._cells.compactMap({ $0 }).first?.table {
                        rows.insert(top + c.rowTop + c.ownRowHeight)
                    }
                }
                return Array(rows.sorted().dropLast()) + [_tops[k] + _heights[k]]
            }
            // (The shift a lifted first line carries — a bullet larger than its text — stands over every line the part
            // can end on, as it does in `_heights`: xb rus-z8098805's p3 row cut a bullet paragraph's lines 4.7pt
            // short, drew its second line half under the foot and again on page 4.)
            let lift = theme.wordRules && RichTextTheme.wordWindowsPages && k < _numberLiftShift.count ? _numberLiftShift[k] : 0
            var lines = Self._lineBottoms(g.painter).map { g.textTop + lift + $0 }
            // (Whatever a raised footer frame does to the body's widows
            // — `widowControlSuspended` — a cell keeps its own: zh-7654804a,
            // whose footer frame stands 47.75pt up, parts its p16 row
            // "…再召開協商會" / "議。" two lines over in Word's print, the
            // cell's "議。" no widow on p17.)
            if (document.compatibilityMode ?? 12) >= 15, document.paragraphs[k].style.widowControl {
                lines = lines.count >= 4 ? Array(lines[1 ..< lines.count - 2]) : []
            } else if !lines.isEmpty {
                lines.removeLast()
            }
            // (A picture wrapped square that hangs from a cell's line is cut with it: the line
            // goes to the next page unless the whole picture fits, as Word's print has it —
            // lo-47598455's fifth 92pt ball, begun at 715 on a foot at 728, opens page 2.)
            var end = _tops[k] + _heights[k]
            if theme.wordRules, RichTextTheme.wordWindowsPages, document.paragraphs[k].cell != nil,
               document.paragraphs[k].text.unicodeScalars.allSatisfy({ $0 == "\u{FFFC}" || $0 == " " || $0 == "\n" }) {
                var images: [ImageAttachment] = []
                if k < _floatImages.count, let image = _floatImages[k] { images.append(image) }
                if k < _inline.count { images += _inline[k] }
                for image in images {
                    if let float = image.float, float.wraps, !float.takesRoom, float.verticalFrom == "paragraph", float.verticalAlign == nil,
                       !image.data.isEmpty {
                        let hang = _tops[k] + _px(float.y) + _px(image.height) + _px(float.effectBottom)
                        if hang > end + 0.01 { RuleTrace.hit("word-cell-line-with-a-square-picture-parts-after-the-picture"); end = hang }
                    }
                }
            }
            return lines + [end]
        }
        // A cell merged down from a row above (Word's `w:vMerge`) is
        // one cell over the rows it covers, and its text is cut at a
        // page's foot like any cell's: when the table goes on to a new
        // page under it, what of it did not fit on the page before goes
        // on from the top of this one.
        func continueSpans(into i: Int, _ c: _CellGeo) {
            defer { prevPartBottom = nil }
            guard theme.wordRules, page > 0 else { return }
            var spans: [[Int]] = []
            var open: (row: Int, column: Int)? = nil
            var k = i - 1
            while k >= 0, let d = _cells[k], d.table == c.table {
                if d.row < c.row, d.row + d.rowSpan > c.row, !d.vertical {
                    if let o = open, o.row == d.row, o.column == d.column {
                        spans[spans.count - 1].insert(k, at: 0)
                    } else {
                        spans.append([k])
                        open = (d.row, d.column)
                    }
                } else {
                    open = nil
                }
                k -= 1
            }
            for members in spans {
                // The cell's pieces on the page before, last first.
                var found: [Int] = []
                var n = _allPieces.count - 1
                while n >= 0, _allPieces[n].paragraph >= members[0] {
                    let piece = _allPieces[n]
                    if piece.page == page - 1, piece.part != .rules, !piece.repeated, members.contains(piece.paragraph) { found.append(n) }
                    n -= 1
                }
                guard let ref = found.first.map({ _allPieces[$0] }) else { continue }
                // That page's foot, in the flow as the cell was set on it.
                // (… or the foot of the table's last row there, where
                // the row after it went over whole: the cell's lines
                // below that go with it.)
                // (A centred cell merged down that runs on below the part keeps only the lines that end no
                // lower than the part, as its neighbours' kept lines close it: lab cm4 (Word for Windows),
                // zh-9ba2ead7 p7's "房屋及设施设备…", whose ninth line stood 15pt under the last line the row
                // keeps there and goes over with the rest in Word's print.)
                let firstMember = _cells[members[0]]!
                let footY = prevContentH - ruleUnder(c, parted: true)
                let closeY = prevPartBottom.map { firstMember.verticalAlign == "center" ? min(footY, $0) : footY } ?? footY
                let limit = ref.flowTop + (min(closeY, prevY) - ref.pageY) + 0.01
                let last = members[members.count - 1]
                guard _tops[last] + _heights[last] > limit else { continue }
                var cut: Double? = nil
                for m in members {
                    let cuts = cellCuts(m), slacks = cellSlacks(m)
                    for (n, b) in cuts.enumerated() where b - (slacks.indices.contains(n) ? slacks[n] : 0) <= limit { cut = max(cut ?? b, b) }
                }
                let shownFrom = found.map { max(_allPieces[$0].flowTop, _tops[_allPieces[$0].paragraph]) }.min() ?? ref.flowTop
                let at = max(cut ?? shownFrom, shownFrom)
                for n in found {
                    let old = _allPieces[n]
                    let m = old.paragraph
                    let top = max(_tops[m], old.flowTop), bottom = _tops[m] + _heights[m]
                    guard bottom > at + 0.01, old.flowBottom > at + 0.01 else { continue }
                    var fresh = PagePiece(paragraph: m, flowTop: max(top, at), flowBottom: bottom, page: page, pageY: y + max(0, top - at))
                    fresh.part = .text
                    // What stays on the page before: the text above the
                    // cut, and the row's rules where this piece drew them.
                    var kept: [PagePiece] = []
                    if top < at - 0.01 {
                        var text = PagePiece(paragraph: m, flowTop: old.flowTop, flowBottom: at, page: old.page, pageY: old.pageY)
                        text.part = old.part == .all ? .text : old.part
                        kept.append(text)
                    }
                    if old.part == .all {
                        var rules = PagePiece(paragraph: m, flowTop: old.flowTop, flowBottom: min(old.flowBottom, limit), page: old.page, pageY: old.pageY)
                        rules.part = .rules
                        kept.append(rules)
                    }
                    _allPieces.replaceSubrange(n ... n, with: kept + [fresh])
                    if let at = _pages[old.page].lastIndex(of: old) { _pages[old.page].replaceSubrange(at ... at, with: kept) }
                    _pages[page].append(fresh)
                }
            }
        }
        var wentOver = false   // `splitRow` moved its row to a new page and left it to the caller
        func splitRow(_ i: Int, _ j: Int, _ c: _CellGeo, atTop: Bool) -> Bool {
            let ts = document.tableStyles[c.table]
            // (A row marked as a header never parts, repeated or not:
            // zh-e37f8d40's form marks every row, so none repeats, and
            // Word carries its 民政局社会救助股意见 row whole to page 14
            // where ours parted it three lines and two.)
            // (Nor a row of exact height that a page could hold: zh-340d52e9's
            // 347pt "守望相助" row (hRule exact) goes whole to page 6 in
            // Word's print with 58pt left on page 5, where ours parted it.)
            guard let ts, !ts.rowsCantSplit.contains(c.row), c.row >= headerRows(c.table),
                  !(theme.wordRules && ts.headerRow && c.row < ts.headerRowCount),
                  !(theme.wordRules && ts.rowsExactHeight.contains(c.row) && c.ownRowHeight <= contentH + 0.01) else { return false }
            // (Nor a row whose first paragraph is kept with the next: lab
            // `kr` (Word 16, modes 15 and legacy), a one-row table of
            // twelve paragraphs with room for eight at a page's foot goes
            // to the next page whole where its first paragraph — the
            // first cell's — says `w:keepNext`, and parts where a middle
            // or last one does, or the second cell's first. form_footnotes'
            // "INSTRUCTIONS" box opens with a Heading 5.)
            // (Unless it is taller than a page, which cannot be kept whole and parts:
            // LibreOffice's tdf170381, a title and a 694pt nested table in one
            // row, parts over two pages in Word's print; kept whole it ran
            // off the first page's foot.)
            // (Not in a table floating by the text: lo-b8885ba2's "Xx Xxxx:" row, a first
            // cell of keepNext, the fourth of five under a floating table, parts at
            // page 5's foot in Word's print. Lab `rowsplit`: in a table in the flow,
            // keepNext alone sends the row whole, with or without keepLines or
            // widow control; zh-604e21e5's and zh-457a8d62's rows are such.)
            if theme.wordRules, document.paragraphs[i].style.keepNext, ts.keptPosition == nil, c.ownRowHeight <= contentH + 0.01 { return false }
            // (Nor a row with a table floating in one of its cells, that a page could hold: lo-5c5eb1f7's
            // "26" row, a float table in each of two cells, goes whole to page 6 in Word's print
            // where ours parted it at page 5's foot.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, c.ownRowHeight <= contentH + 0.01 {
                for k in i ..< j {
                    let q = document.paragraphs[k]
                    for image in q.inlineImages.inOrder + [q.image].compactMap({ $0 }) {
                        if image.textBox?.growsToFit == true, image.float != nil { RuleTrace.hit("row-with-a-floating-table-in-a-cell-goes-whole"); return false }
                    }
                }
            }
            // (Nor where the page's footer holds a sized, raised frame and
            // reaches above its bottom margin:
            // there Word parts no row at the page's foot, but sends it to the
            // next page whole, and parts it there only if it is taller than a
            // page. zh-73534289's footer — a framed page number and an empty
            // 12pt paragraph 720 twips up — stands 0.4pt over its 851-twip
            // margin, and no row of its 118-row table is parted in Word's
            // print; ours parted them and pp28-33 ran out of step. Labs
            // `rw`/`rw2` (Word for Windows, its package): a fresh one-row
            // table of a page and a half goes whole to the next page and
            // parts from there; with the footer 200 twips up, or the margin
            // 1100, it parts at the foot of the first; at 980 it does not;
            // with the frame taken out of the footer it parts. Only a frame
            // of a stated width raised over its anchor (w:y below 0): the same
            // frame auto-sized, or at y 1, parts the row; one 3000 twips wide
            // at y -2 does not. Most page numbers are auto-sized frames at
            // y 1, centred on the margin, and their rows part: taken for any
            // frame the rule cost some forty documents.)
            // (So does an auto-sized frame, wrapped round, where raised over
            // its anchor, in Word for Mac's prints: lab `wr` (the Mac, zh-9462c6d6's package), its
            // "- N -" frame at y -15 reaching 8.3pt over the 851 margin —
            // the row goes whole at 17, 20 and 33pt above the margin in
            // modes 14 and 15, and parts at 20 without the footer. Not a
            // frame wrapped "auto": zh-7654804a's, raised 955 twips, parts
            // its p16 row in Word's print.)
            // (A row under nothing but repeated header rows is at the page's top.)
            if theme.wordRules, !atTop, !_pages[page].allSatisfy({ $0.repeated }), let footer = _headerFooter(.footer, page: page, document, pageCount: 1),
               footer.document.paragraphs.contains(where: { p in
                   p.cell == nil && p.style.frame.map { $0.y < 0 && ($0.width != nil || (p.style.frameXML ?? "").containsSubstring("w:wrap=\"around\"")) } == true }),
               _bodyInsets(page: page, document).bottom > _px(pageSetup(forPage: page).marginBottom) + 0.01 {
                return false
            }
            // (A turned cell does not keep its row whole: zh-021b8feb's
            // "職場人力協助" row, its first cell turned (tbRlV), parts at
            // page 17's foot in Word's print, where ours took it whole to
            // page 18 and the table ran onto a 19th.)
            if !theme.wordRules { for k in i ..< j { guard let d = _cells[k], !d.vertical else { return false } } }
            var fresh = atTop
            let rowBottom = c.rowTop + c.ownRowHeight
            struct Column { var members: [Int]; var cuts: [Double]; var bottom: Double; var cut: Double; var owners: [Int] = []; var slacks: [Double] = [] }
            // (The top margins and lines of the nested cells a part that goes over a page is still in: it is
            // set under them again — see `RichParagraphStyle.nestedTopRepeat`.)
            func nestedRepeat(_ column: Column) -> Double {
                guard theme.wordRules, let k = column.members.first(where: { _tops[$0] + _heights[$0] > column.cut + 0.01 }) else { return 0 }
                return _px(document.paragraphs[k].style.nestedTopRepeat)
            }
            // (What a part that goes on to the next page is held clear of the foot by, besides the nested cells' own
            // bottoms: the outer cell's top margin under its rule and the nested tops, which the next part stands
            // under again — Word ends lo-c7082c66's page 3 a line sooner than the bottoms alone allow; 0.3 of the cell's top margin more is fitted to lab nf1
            // (Word for Windows, margins 0 / 113 / 300 twips: pages 1-3 end where Word's do; a flat 3pt broke the 0 one).)
            func nestedGap(_ column: Column) -> Double {
                let r = nestedRepeat(column)
                guard r > 0 else { return 0 }
                return r + max(0, _cells[column.members[0]]!.pad.top - ruleUnder(c, parted: true)) + 0.3 * _cells[column.members[0]]!.pad.top
            }
            // (A flattened row, a floating table's, is no shorter than its least height on EACH page its part stands on:
            // lab nf1, Word for Windows — the last part of lo-c7082c66's float row, six lines on page 4, stands 169.6pt
            // tall, its least height, and the cell's next paragraphs under that.)
            func partPad(_ column: Column) -> (at: Double, amount: Double)? {
                guard theme.wordRules else { return nil }
                for k in column.members {
                    guard let least = document.paragraphs[k].style.blockMinHeight, _tops[k] < column.cut - 0.01 else { continue }
                    let end = _tops[k] + _heights[k]
                    guard end > column.cut + 0.01 else { continue }
                    let amount = _px(least) - (end - column.cut)
                    if amount > 0.01 { return (end, amount) }
                }
                return nil
            }
            func nestedFoot(_ owner: Int) -> Double {
                guard theme.wordRules, owner >= 0, owner < document.paragraphs.count else { return 0 }
                return _px(document.paragraphs[owner].style.nestedBottomRepeat)
            }
            var columns: [Column] = []
            for k in i ..< j {
                let d = _cells[k]!
                if columns.isEmpty || _cells[columns[columns.count - 1].members[0]]!.column != d.column {
                    columns.append(Column(members: [], cuts: [], bottom: 0, cut: c.rowTop))
                }
                columns[columns.count - 1].members.append(k)
                let own = cellCuts(k)
                columns[columns.count - 1].cuts.append(contentsOf: own)
                columns[columns.count - 1].owners.append(contentsOf: repeatElement(k, count: own.count))
                columns[columns.count - 1].slacks.append(contentsOf: cellSlacks(k))
                // (A cell merged down has the rows below for the rest.)
                columns[columns.count - 1].bottom = d.rowSpan > 1 ? min(rowBottom, _tops[k] + _heights[k] + d.pad.bottom)
                    : _tops[k] + _heights[k] + d.pad.bottom
            }
            let repeats = c.row > 0 && headerRows(c.table) > 0
            var pieces: [Int: [PagePiece]] = [:]
            var rules: [PagePiece] = []
            var lift = 0.0   // the line a part that went over opens with
            // (Columns set whole in a part already — a cell merged down
            // whose text, centred over its rows, reaches past this row's
            // own bottom: zh-13552a3a's "4.就业失业登记", merged over rows
            // 10-11, stands whole in row 10's part at page 15's foot in
            // Word's print, and once; ours drew "失业登/记" again at page
            // 16's head, the lines past row 10's bottom in the flow.)
            var doneWhole = Set<Int>()
            var ghostLeft = 0.0   // the rows merged down under it that went over whole
            var first = true
            while true {
                var avail = contentH - y
                // (A table floating by the text and raised over its place, up past the
                // margin: Word sets the page's room by the place it would have stood,
                // not the raised one, so the page ends as much sooner as the raise.
                // LibreOffice's lo-1709e655, tblpY -345 twips, one cell of 60 lines:
                // 48 on the page in Word's print, 50 in ours.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, first, let ts = document.tableStyles[c.table],
                   ts.floatsOverText, ts.floatOffsetY == nil, !ts.pageAnchored, let up = ts.floatRaiseY, ts.rowsExactHeight.isEmpty,
                   let top = _pages[page].filter({ !$0.repeated && _cells[$0.paragraph]?.table == c.table }).map(\.pageY).min(), top < -0.01,
                   // (A table taller than the page only: one that ends on it keeps
                   // its room — lo-3b33e295's two small raised tables.)
                   case let whole = (0 ..< count).compactMap({ k in _cells[k].flatMap { $0.table == c.table ? $0.rowTop + $0.ownRowHeight : nil } }).max() ?? 0,
                   whole > contentH + 0.01, c.ownRowHeight > avail + 0.01, _columnWidths[c.table]?.count == 1 {
                    avail -= min(_px(up), -top)
                }
                // (A table placed against the page whose rows from here on
                // end above the footer's place sets them on this page, past
                // the margin: zh-0b87285b's 13-row list ends 524.9pt down a
                // 595pt page in Word for Windows' print, margin at 523 and
                // footer at 545.4 — `anchoredParts` keeps its head with it,
                // and ours sent its last row alone to page 7, its title
                // after it.)
                if theme.wordRules, first, document.tableStyles[c.table]?.pageAnchored == true {
                    var bottom = c.rowTop + c.ownRowHeight, k = i
                    while k < count, let d = _cells[k], d.table == c.table { bottom = max(bottom, d.rowTop + d.ownRowHeight); k += 1 }
                    // (A row alone, in Word for Windows: LibreOffice's
                    // floattable-compat14, two rows of eight lines placed
                    // 164pt down a 318pt page, has the first whole on page 1,
                    // 272pt down — past the margin at 246, above the footer's
                    // place at 283 — and the second on page 2.)
                    // (The table's first row only: zh-3ab8a2fb's fifth row, 62pt
                    // from the footer's place, goes over whole in Word's print.)
                    if RichTextTheme.wordWindowsPages, c.row == 0 { bottom = c.rowTop + c.ownRowHeight; for m in i ..< j { if let d = _cells[m] { bottom = max(bottom, d.rowTop + d.ownRowHeight) } } }
                    let setup = pageSetup(forPage: page / _columns)
                    let edge = pageEdgeClamp?.table == c.table ? pageEdgeClamp!.edge : max(contentH, _px(setup.height - setup.footerDistance) - _bodyInsets(page: page / _columns, document).top)
                    // (Not far past the margin: LibreOffice's floattable-then-table, a
                    // page-anchored table of two 200pt rows on a page whose margin is
                    // 123pt, has its second row 70pt over the margin and above the
                    // footer's place, and Word's print parts it onto page 2; the 26pt
                    // of floattable-compat14 stays.)
                    // (And a row that parts by lines goes on to the footer's place as well, where the table
                    // starts on this page: LibreOffice's floattable-avoid-last-manip-ofst, a landscape 612pt page,
                    // margin at 540 and footer at 576.6, keeps three more lines of a row on page 1 in Word for
                    // Windows' print, at 536.9, 550.3 and 563.7; its pages 2 to 5 stop at 515, whole rows.)
                    let startsHere = c.row == 0 || _pages[page].contains { piece in
                        !piece.repeated && _cells[piece.paragraph].map { $0.table == c.table && $0.row == 0 } == true }
                    // (Not from 2013's layout on: LibreOffice's floattable-avoid-last-manip-ofst has no compatibility
                    // mode and goes past the margin; its two like tables in mode 15 stop at the margin in Word's print.)
                    // (Not a row that holds a table nested in it with slack of its own: labs nt1b, the margin moves its cut and
                    // the footer's distance does not.)
                    let nestedSlack = columns.contains { $0.slacks.contains { $0 > 0 } }
                    // (And to the page's own foot, not the footer's place: lab ft1 (Word for Windows, compat 12): a line stays
                    // while its bottom is within the page height, wherever the margin and footer stand — a row opening 20pt
                    // above the margin keeps 7 lines to 611.9 on a 612pt page, one opening 600pt down keeps one, 606 keeps none.)
                    // (Not a row with a height of its own: LibreOffice's lo-e3dca7be, a one-line 1014-twip row 2pt above the margin of a
                    // 395pt page, goes whole to page 2 in Word's print, where the page's foot would hold it.)
                    let byLines = RichTextTheme.wordWindowsPages && startsHere && !nestedSlack && (document.compatibilityMode ?? 12) < 15
                    // (A row of eight lines under a stated 1014 twips grows by its text, and parts by lines like one with none:
                    // lo-c9b8c5ab's A5, four lines on page 1 to 594 on a 612pt page in Word's print.)
                    let growsPastStated = document.tableStyles[c.table]?.rowHeights[c.row].map { c.ownRowHeight > _px($0) + _px(2) } ?? true
                            if byLines, growsPastStated {
                        // (Lab c9b, Word for Windows: with a height stated, a line stays while its bottom is within 66.5pt of the
                        // margin's edge — 4 lines at margins 528 to 541 on a 612pt page, 5 at 544, 3 at 527 — whatever the page height.)
                        let stated = document.tableStyles[c.table]?.rowHeights[c.row] != nil
                        let limit = stated ? contentH + _px(66.5) : _px(setup.height - 14) - _bodyInsets(page: page / _columns, document).top
                        avail = max(avail, max(edge, limit) - y)
                    } else if byLines || y + (bottom - c.rowTop) <= edge + 0.01 && (c.row == 0 || y + (bottom - c.rowTop) - contentH <= _px(40)) && !(RichTextTheme.wordWindowsPages && (document.compatibilityMode ?? 12) >= 15 && c.row > 0) { avail = max(avail, edge - y) }
                }
                // (What goes over is a row again, and no shorter than
                // the file says a row is: the second half of a row of
                // 28.5pt at least is 28.75 at the head of Word's page.)
                // (With the line it opens with: 29.4 from the page's head.)
                // (Its cells' margins on top of the height, as the whole
                // row's are — labs `rm1`-`rm3`: an "at least" height is
                // the room between the margins. zh-b378d8c4's 专栏5, one
                // row of at least 132.05pt with 15-twip margins parted
                // over pages 12 and 13, goes on 134.4pt down page 13 in
                // Word's print; ours, without the margins, 133.0, and the
                // page after it a line long.)
                let margins = theme.wordRules
                    ? columns.map { column -> Double in let d0 = _cells[column.members[0]]!; return d0.pad.top + d0.pad.bottom }.max() ?? 0 : 0
                // (Word for Windows: the part goes on at the stated height, its
                // own top rule — the line it draws at the page's head, the
                // row above's bottom one staying behind — and its cells'
                // margins as stated. Lab trow (windows-1): at least 138pt with
                // no margins, 0.25/0.5/1pt rules, goes on 138.26/138.50/138.98;
                // with 0.75pt margins 139.82/140.06/140.54; zh-13552a3a's cells,
                // their top nil under a ruled row, go on at 138.03 — ours, the
                // row above's line taken for theirs, at 138.5.)
                let windowsExtra: Double? = theme.wordRules && RichTextTheme.wordWindowsPages ? columns.map { column -> Double in
                    let d0 = _cells[column.members[0]]!
                    return d0.ownTopRule + max(0, d0.pad.top + d0.pad.bottom - d0.rules)
                }.max() : nil
                let stated = ts.rowsExactHeight.contains(c.row) || ts.rowHeights[c.row] == nil ? 0
                    : min(c.ownRowHeight, _px(ts.rowHeights[c.row]!) + (windowsExtra ?? max(c.rules - c.ruleBelow, margins - c.ruleBelow, 0)))
                // (And no shorter than a cell merged down into it whose
                // text went over with it, as a whole row is not — see
                // `pageHeight`: zh-e6d54ae4's "（三）注重服務人員…" is merged
                // over two rows, the second parts over the page, and the
                // part that goes over is one line of its own with three
                // of the merged cell beside it; the next row stood over
                // them.)
                // (… and where the row went over whole, too, and is laid
                // out again at the page's head: zh-e6d54ae4's row "3.旅服
                // 中心每半年…" has no line at page 5's foot, and the cell
                // merged down beside it takes five lines over with it; the
                // row stood at its own height and the next row over the
                // last of them, "施。".)
                var carried = 0.0
                if theme.wordRules, !first || fresh {
                    for piece in _pages[page] where piece.part != .rules && piece.paragraph < i && !piece.repeated {
                        let m = piece.paragraph
                        guard let d = _cells[m], d.table == c.table, d.row < c.row, !d.vertical,
                              (c.row ... c.row + c.ghostRows).contains(d.row + d.rowSpan - 1) else { continue }
                        carried = max(carried, piece.pageY + (min(piece.flowBottom, _tops[m] + _heights[m]) - piece.flowTop) + d.pad.bottom - y)
                    }
                }
                let left = max(carried, columns.map { column in
                    // (With the cell's top margin under the rule again —
                    // see where the pieces are set below.)
                    max(0, column.bottom + (partPad(column)?.amount ?? 0) - column.cut)
                        + (theme.wordRules ? max(0, _cells[column.members[0]]!.pad.top - ruleUnder(c, parted: true)) + nestedRepeat(column) : 0)
                }.max() ?? 0)
                // (A part whose text fits is no taller than the room to the
                // foot, though the row states more: zh-045c5a75's row of at
                // least 779.75pt — more than a page — runs over pages 4 to 7,
                // and Word ends it at page 7's foot; ours padded the last
                // part to the stated height, which went over again and made
                // page 8 blank.)
                // (… and no shorter than the rows merged down under it that
                // went over whole, where it parted at one's top — lab `mg`:
                // zh-9ef811c8's 81pt row stands whole at page 5's head, the
                // next table head 34pt lower than under ours, which kept only
                // the three lines left of its cells.)
                let rest = first ? (carried > 0 ? max(c.ownRowHeight - c.stretched, carried) : c.ownRowHeight)
                    : max(theme.wordRules && left + ruleUnder(c) <= avail + 0.01 ? min(stated, avail - ruleUnder(c)) : stated, left, ghostLeft)
                // (A part, or the row on the next page, goes under a pinned
                // float it would run into, as a whole row does.)
                if !pinBands.isEmpty {
                    underPins(rest)
                    avail = contentH - y
                }
                var fits = rest + ruleUnder(c) <= avail + 0.01
                // (A section's columns, set as a row, fit as the body's
                // paragraphs do: the space after each column's last
                // paragraph may stand past the foot. zh-8f9b19f4 ends in
                // three columns, "填报人：" | "审核人：" | "负责人：", 31.4pt
                // over a foot with no margin under it; their lines end 25.3
                // down and their 8pt after at 33.3, and Word prints all
                // three on page 14 — ours parted the row onto a page 15.)
                if !fits, theme.wordRules, first, carried == 0, document.tableStyles[c.table]?.sectionColumns == true,
                   columns.map({ column -> Double in
                       let last = column.members[column.members.count - 1]
                       return _tops[last] + _heights[last] - _spacing(last, document).after - c.rowTop
                   }).max() ?? .infinity <= avail + 0.01 {
                    fits = true
                }
                // A row is not begun where the height the file states
                // for it has no room: it goes to the next page whole,
                // though a line of each cell would fit (prints of
                // 2026-10-13: a row of 49.65 at least with 36.5 left
                // goes over, one of 25 at least parts, as one with no
                // height does — whatever its cells' alignment, and a
                // cell merged down into it leaves its lines with it).
                // (With its rule under it as well as the one over it, even
                // where the row parts and its part would take none — lab
                // t206, Word for Windows: zh-dc9cfa34's row 43, at least
                // 39.55pt under 0.5pt rules, goes over whole with 40.3
                // left; at least 22 parts with 24.2 left and 23.5 does not.)
                if let traced = Self.debugRows, traced == page + 1 {
                    FileHandle.standardError.write(Data("split row \(c.row): first \(first) fresh \(fresh) y \(y / _px(1)) stated \(stated / _px(1)) avail \(avail / _px(1)) fits \(fits) rest \(rest / _px(1)) ghostBounds \(c.ghostBounds.map { $0 / _px(1) })\n".utf8))
                }
                // (A row that opens a page of a table with no top line of its own
                // does not keep the room of the inside line above it, which Word
                // neither draws nor reserves there: zh-37b6536f p5, row 12 under
                // outset inside lines, 0.9pt high in ours.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, first, fresh, y < 0.01, c.firstInRow, c.row > 0, !repeats,
                   let ts = document.tableStyles[c.table], ts.edges?.top == false, c.rules > 0.01, c.rules <= _px(2) {
                    y -= c.rules
                }
                if first, !fresh, y > 0.01, stated > 0, stated + max(ruleUnder(c), theme.wordRules ? c.ruleBelow : 0) > avail + 0.01 {
                    newPage()
                    if repeats { repeatHeader(of: c.table, before: i) }
                    if c.row > 0 { continueSpans(into: i, c) }
                    wentOver = true
                    return false
                }
                // (A row that the rows merged down under it run on through,
                // rows that hold nothing of their own, parts only where one
                // of them begins: its text fills the rows that fit, and the
                // next goes over whole. Lab `mg` on Word for Windows,
                // zh-9ef811c8's table: its "监督检查" row (15.6pt) and the
                // three under it (15.6, 53.1, 81) part at the 81pt row's top,
                // 84.3pt down, its lists five lines on the page, and three
                // lines lower they part after the second. Ours parted the
                // 81pt row, six lines on the page, and centred what then
                // fitted.)
                // (The part is then that tall, whatever its cells keep: the
                // rows that fit go with it whole.)
                var ghostPart: Double? = nil
                if theme.wordRules, first, !fits, !c.ghostBounds.isEmpty,
                   let bound = c.ghostBounds.last(where: { $0 + ruleUnder(c) <= avail + 0.01 }) {
                    // (With the rule a part closes with, whole: zh-9ef811c8's "8" row, a
                    // 15.6pt row and the 0.5 over it, stands on page 6 with its one-line cells and
                    // its marks in Word's print, the merged lists of ten lines all on page 7.)
                    avail = bound + (RichTextTheme.wordWindowsPages ? max(ruleUnder(c), ruleUnder(c, parted: true)) : ruleUnder(c))
                    ghostPart = bound
                    ghostLeft = c.ownRowHeight - bound
                    // (Where it ends at the rows' own heights, what goes
                    // over is the last of them again, as tall as the file
                    // says it is: zh-9ef811c8's "审批" rows send two lines
                    // over, and Word's page 7 stands them in the 48.95pt
                    // row, the next row 17.7pt lower than under ours.)
                    let last = c.row + c.ghostRows
                    if bound == c.ghostBounds.last, c.stretched > 0.01, let h = ts.rowHeights[last], !ts.rowsExactHeight.contains(last) {
                        ghostLeft = max(ghostLeft, _px(h) + max(c.rules - c.ruleBelow, margins - c.ruleBelow, 0))
                    }
                }
                // A centred cell (or one set at the bottom) that does not fit
                // the part is parted from its text's top, at the part's top:
                // Word sets zh-1a3c7aa0's row 328 name cell — three lines
                // centred in a row of 305pt — two lines at the head of the
                // part on page 82 and one on the next; parted where the
                // flow centres it, its first line fell below the foot and
                // the row went over whole.
                // (Not before Word 2007's layout, mode 12: zh-64044a1d, mode
                // 11, takes its "電力組" row over whole with a line of each
                // cell fitting at page 19's foot — why is not known; the
                // modes this was seen in are 12 and 15.)
                if theme.wordRules, first, !fits, (document.compatibilityMode ?? 12) >= 12 {
                    for n in columns.indices where columns[n].cut <= c.rowTop + 0.01 {
                        let d0 = _cells[columns[n].members[0]]!
                        // (A cell merged down too: zh-4d143b5e's row 11, its
                        // first three cells centred and merged over six rows,
                        // parts at page 6's foot in Word's print with two
                        // lines of every cell there, from the row's top —
                        // where centring over the six rows put their first
                        // lines below the foot and the row went over whole.)
                        guard !d0.vertical, d0.verticalAlign == "center" || d0.verticalAlign == "bottom" else { continue }
                        let blockTop = _tops[columns[n].members[0]]
                        let blockBottom = _tops[columns[n].members[columns[n].members.count - 1]] + _heights[columns[n].members[columns[n].members.count - 1]]
                        let room = avail - ruleUnder(c, parted: true) - d0.pad.top - d0.pad.bottom - (blockBottom - blockTop)
                        // (Only for a row begun under other text: one that opens a
                        // page keeps its centring — zh-e37f8d40's "乡镇社会事务
                        // 办公室核查意见" stands mid-cell at page 12's head.)
                        // (And only where a line of it fits there: with none, what
                        // goes over is centred in the part over the page, as the
                        // flow has it — zh-e37f8d40's "乡镇社会事务办公室核查意见"
                        // at page 12's head, its row begun on page 11.)
                        // (Or one that opens it and is taller than it all the
                        // same, which parts wherever it begins: zh-0978dee9's
                        // row 79 opens page 280, its four long cells centred
                        // in a row of two pages, and Word's print sets their
                        // text from the row's top there; centred in the whole
                        // row, ours stood 3 to 48pt down the page.)
                        let start = max(c.rowTop, blockTop - d0.pad.top)
                        let limit = start + avail - ruleClosing(c) + 0.01
                        let partsAnyway = fresh && c.ownRowHeight + ruleUnder(c) > avail + 0.01
                        if room < -0.01, (!fresh && y > 0.01) || partsAnyway, columns[n].cuts.contains(where: { $0 > start + 0.01 && $0 <= limit }) {
                            columns[n].cut = start
                        }
                    }
                }
                var next = columns.map(\.cut)
                var setWhole: [Int: Double] = [:]   // column → pageY of flow 0, for one set whole in this part
                if !fits {
                    // (Every cell with something left must take some of
                    // it: where one cannot — a paragraph that may not
                    // part there — the row goes to the next page whole.
                    // On a page of its own it takes what it can.)
                    var moved = false, stuck = false
                    for (n, column) in columns.enumerated() {
                        // (Under the table's STATED bottom cell margin and a point more, in a FLOATING table in Word for Windows — tdf170672's last baselines never pass 508.9 on a 518.75 foot in 129 pages, ours stood to 515.5 at the margin alone; a point more takes it 36 -> 65, floattable-negative-height 74 -> 100 (1 to 2.5 all do the same); and — zh-15f60bac's ordinary one stands to the foot: tdf170672's one 18-row table,
                        // 5.4pt from its style, ends each page's part of a row 9.9pt or more over the foot, 129 samples,
                        // where ours put lines to 3.8pt from it. Not the cell's own `pad.bottom`, which holds more than
                        // the margin: it cost 33 government documents; the stated one moves none of the 34 that state one.)
                        let bottomMargin = RichTextTheme.wordWindowsPages && theme.wordRules && document.tableStyles[c.table]?.keptPosition != nil ? _px(document.tableStyles[c.table]?.cellMarginBottom.map { $0 > 0 ? $0 + 1 : $0 } ?? 0) : 0
                        // (A part that goes on from the page before draws the cell's top margin again above its
                        // first line, and the room it is cut by never counted it: tdf170672's p9 kept a line 1.5pt
                        // under the last Word's print keeps, cut slack 94 against 178 for the lines it keeps.)
                        let contTop = RichTextTheme.wordWindowsPages && theme.wordRules && document.tableStyles[c.table]?.keptPosition != nil && column.cut > c.rowTop + 0.01 ? _cells[column.members[0]]!.pad.top : 0
                        let limit = column.cut + avail - ruleUnder(c, parted: true) - bottomMargin - contTop + 0.01
                        // (A cut, under the line the part is closed with —
                        // where the cell ends here, its own bottom has it.)
                        // (To Word for Windows' raster: it sets rows on a 1/600in grid
                        // from the running total (lab round), so a cut that rounds to the
                        // foot's dot is on the page — zh-4c5da793 p15's row "对抚恤优待对象
                        // 冒领…" keeps its second line in Word's print, 0.09pt past ours,
                        // its row standing 0.11 high.)
                        let closed = column.cut + avail - ruleClosing(c) - bottomMargin - contTop + 0.01
                        // (The foot's dot, to which a cut that rounds is on the page —
                        // to carry a cell's cut a line further in the same paragraph
                        // only: a cell's whole bottom is measured as before, a cell with
                        // no cut gets none by it, and none reaches a paragraph after —
                        // zh-4a90bb2f's "领导小组意见" row lost its label to the next page.)
                        let cutClosed: Double = {
                            guard RichTextTheme.wordWindowsPages, _px(1) > 0 else { return closed }
                            let dot = _px(72.0 / 600)
                            return max(closed, ((closed - 0.01) / dot).rounded() * dot + dot / 2 - 0.001)
                        }()
                        let d0 = _cells[column.members[0]]!
                        let blockTop = _tops[column.members[0]]
                        let blockBottom = _tops[column.members[column.members.count - 1]] + _heights[column.members[column.members.count - 1]]
                        let room = avail - ruleUnder(c, parted: true) - d0.pad.top - d0.pad.bottom - (blockBottom - blockTop)
                        // (Merged down over the rows below, too, where its text
                        // has no cut in the part: zh-540dc149's "（3）桥隧（8分）",
                        // centred over its row and the next, stands centred in
                        // its row's part on page 5 in Word's print, the row
                        // parting under it; ours had no line of it to keep there
                        // and sent the row over whole.)
                        // (Or merged only over rows that hold nothing of
                        // their own, the row's ghosts, and all of it fitting
                        // the part: lab `mg`, zh-9ef811c8's "●社会救助信访通讯
                        // 地址…", five lines centred over the four rows, is set
                        // whole in the part on p4 in Word's print, where ours
                        // parted it where centring over the four put it, two
                        // lines on the page. Not over rows with lines of their
                        // own: that cost zh-e37f8d40, which has none of these.)
                        // (A centred cell merged down whose text all stands inside the
                        // page, beside a cell of the row that parts: Word for Windows
                        // keeps it whole on the table's first page, centred in the
                        // part there, never its lines split at the cut. Lab `cm1`,
                        // ten tables: three lines centred over two rows beside a
                        // right cell of fourteen lines and more, baselines 142.37,
                        // 157.03, 171.67 on page 1 in every one.)
                        let centredInPart = theme.wordRules && RichTextTheme.wordWindowsPages && d0.rowSpan > 1 && d0.verticalAlign == "center"
                            && room >= -0.01 && c.ghostRows == 0
                        let wholeMerged = d0.rowSpan > 1 && (!column.cuts.contains { $0 > column.cut + 0.01 && $0 <= limit }
                            || d0.rowSpan - 1 <= c.ghostRows || centredInPart)
                        if centredInPart, wholeMerged { RuleTrace.hit("word-centred-merged-cell-stays-whole-on-the-first-page") }
                        if theme.wordRules, column.cut <= c.rowTop + 0.01, d0.rowSpan == 1 || wholeMerged, !d0.vertical,
                           d0.verticalAlign == "center" || d0.verticalAlign == "bottom", room >= -0.01 {
                            // A centred cell (or one set at the bottom)
                            // whose text all fits the row's part on this
                            // page is set there, in that part: zh-64044a1d's
                            // "警政組" stands midway between the two lines
                            // of its neighbour that Word keeps on the page,
                            // where centring it in the whole row put it
                            // over the foot and sent the row over whole.
                            // Wherever centring in the whole row would put
                            // it, too: zh-1a3c7aa0's row numbers "65" (p22)
                            // and "127" (p51) stand midway in the row's part
                            // on the page in Word's print, 25pt above where
                            // the whole row's middle put them.
                            setWhole[n] = y + d0.pad.top + max(0, room) * (d0.verticalAlign == "center" ? 0.5 : 1) - blockTop
                            next[n] = max(column.cut, rowBottom)
                            moved = true
                        } else if column.bottom + (partPad(column)?.amount ?? 0) <= (RichTextTheme.wordWindowsPages ? closed : limit),
                                  // (Not a cell merged down whose text was parted from its top, below this
                                  // row's own bottom — its bottom is the row's, and none of it is placed
                                  // yet: lab `cms` (Word for Windows, zh-785e46f8's table), "用地、/用能、/
                                  // 环境" centred over seven rows, the first parting at the foot with two
                                  // lines on the page, stands from the part's top two lines there and one
                                  // under the repeated header; ours sent all three over.)
                                  // (`partedBelow`.)
                                  !(theme.wordRules && RichTextTheme.wordWindowsPages && d0.rowSpan > 1 && column.cut > c.rowTop + 0.01 && column.cut >= column.bottom - 0.01 && first),
                                  // (Nor one merged down whose bottom is only the row's, its own last line
                                  // standing past it: zh-4d143b5e's "有计划…理想信念、统计法制…" over two rows,
                                  // five lines to a part that holds two, was set whole on p6 with its third
                                  // line under the foot and again from the top of p7; Word cuts after the
                                  // second line.)
                                  !(theme.wordRules && RichTextTheme.wordWindowsPages && d0.rowSpan > 1 && (column.cuts.last ?? 0) > column.bottom + 0.01) {
                            // (All that is left of this cell is on this page.)
                            // (Above the line the part is closed with, as a cut
                            // must be: zh-e1b09977's p13 closes under its table's
                            // 2.16 bottom in Word for Windows' print, and item 五's
                            // "措施。" goes to p14 with 0.5pt short of that; ours
                            // measured it against the half-point line and kept it.
                            // Lab t190: with 1.0 more room it stays.)
                            if column.bottom > column.cut + 0.01 { moved = true }
                            next[n] = max(column.cut, rowBottom)
                        } else if let at = column.cuts.indices.last(where: { column.cuts[$0] > column.cut + 0.01 && column.cuts[$0] - (column.slacks.indices.contains($0) ? column.slacks[$0] : 0) <= closed - (theme.wordRules && bottomMargin == 0 ? d0.margin : 0) - (theme.wordRules && bottomMargin == 0 && (document.compatibilityMode ?? 12) >= 15 ? (column.cuts[$0] >= column.bottom - d0.pad.bottom - 0.01 ? d0.pad.bottom : (d0.rowSpan == 1 && !_cells.contains { $0?.table == d0.table && ($0?.rowSpan ?? 1) > 1 } ? max(0, d0.pad.bottom - d0.ruleBelow) : 0)) : 0) - nestedFoot(column.owners.indices.contains($0) ? column.owners[$0] : -1) - nestedGap(column) }),
                                  case let owner = column.owners.indices.contains(at) ? column.owners[at] : -1,
                                  let cut = column.cuts.indices.filter({ $0 >= at && (column.owners.indices.contains($0) ? column.owners[$0] : -1) == owner })
                                    .last(where: { column.cuts[$0] - (column.slacks.indices.contains($0) ? column.slacks[$0] : 0) <= cutClosed - (theme.wordRules && bottomMargin == 0 ? d0.margin : 0) - (theme.wordRules && bottomMargin == 0 && (document.compatibilityMode ?? 12) >= 15 ? (column.cuts[$0] >= column.bottom - d0.pad.bottom - 0.01 ? d0.pad.bottom : (d0.rowSpan == 1 && !_cells.contains { $0?.table == d0.table && ($0?.rowSpan ?? 1) > 1 } ? max(0, d0.pad.bottom - d0.ruleBelow) : 0)) : 0) - nestedFoot(column.owners.indices.contains($0) ? column.owners[$0] : -1) - nestedGap(column) }).map({ column.cuts[$0] }) {
                            // (Under the cut, the cell's bottom margin, as
                            // the part is closed with it: zh-12f87285's
                            // cells state 1.2pt, and Word leaves a line
                            // 0.9pt clear of the foot, less that, for the
                            // next page — p6, p16, p26, p28.)
                            next[n] = cut
                            moved = true
                        } else if theme.wordRules, RichTextTheme.wordWindowsPages, ghostPart != nil, d0.rowSpan > 1, d0.rowSpan - 1 <= c.ghostRows {
                            // (A cell merged down over the rows that part here, none of whose
                            // lines fits in them, goes over whole with the rest of its rows.)
                            next[n] = column.cut
                        } else {
                            stuck = true
                            if let traced = Self.debugRows, traced == page + 1 {
                                FileHandle.standardError.write(Data("stuck-detail col \(n): align \(String(describing: d0.verticalAlign)) rowSpan \(d0.rowSpan) pad \(d0.pad.top / _px(1)) \(d0.pad.bottom / _px(1)) block \((blockBottom - blockTop) / _px(1)) room \(room / _px(1)) avail \(avail / _px(1)) cutVsRowTop \((column.cut - c.rowTop) / _px(1)) wholeMerged \(wholeMerged) closed \((closed - column.cut) / _px(1))\n".utf8))
                            }
                        }
                    }
                    // (A cell merged down keeps only the lines whose foot is
                    // inside the row's piece on this page — the row's stated
                    // height or what its own cells keep, whichever is more —
                    // not every line the page would hold: lab vmp (Word for
                    // Windows, zh-e6d54ae4's table, row 6 of 39.9pt with
                    // "（二）提供民眾易讀…" merged over three rows on an 18pt
                    // grid beside an unmerged item cell): pieces of 40.3 and
                    // 47.3 keep two of its lines, the whole 62.9 three; its
                    // own p2 keeps two, ours three. Top-aligned cells only;
                    // a centred one is set above.)
                    if theme.wordRules, RichTextTheme.wordWindowsPages, first {
                        let own = columns.indices.filter { _cells[columns[$0].members[0]]!.rowSpan == 1 }
                        if !own.isEmpty, own.contains(where: { next[$0] < rowBottom - 0.01 }) {
                            let statedBottom = ts.rowHeights[c.row].map { c.rowTop + _px($0) } ?? c.rowTop
                            let bound = max(statedBottom, own.map { next[$0] >= rowBottom - 0.01 ? columns[$0].bottom : next[$0] }.max()!)
                            for n in columns.indices where setWhole[n] == nil {
                                let d0 = _cells[columns[n].members[0]]!
                                guard d0.rowSpan > 1, !d0.vertical, d0.verticalAlign != "center", d0.verticalAlign != "bottom",
                                      next[n] > bound + 0.01 || (next[n] >= rowBottom - 0.01 && columns[n].bottom > bound + 0.01) else { continue }
                                next[n] = columns[n].cuts.last(where: { $0 > columns[n].cut + 0.01 && $0 <= bound + 0.01 }) ?? columns[n].cut
                            }
                        }
                    }
                    // (The part on this page is as tall as what its other
                    // cells keep here — their last kept line and their
                    // margin — not the room to the page's foot: Word
                    // draws the part's bottom rule there and centres in
                    // it. zh-1a3c7aa0's "65" on p22, 5pt low when centred
                    // to the foot.)
                    // A longer centred cell may already have had its cut
                    // moved to its text's top above. It is still the first
                    // part: its kept lines, not the space to the page foot,
                    // determine where its short neighbours are centred.
                    // bug65649's row 19 otherwise puts them 4.7pt too low.
                    if theme.wordRules, first, !setWhole.isEmpty {
                        let kept = columns.indices.filter { setWhole[$0] == nil }.map { n -> Double in
                            let column = columns[n]
                            let end = next[n] >= rowBottom - 0.01 ? column.bottom + (partPad(column)?.amount ?? 0) : next[n] + _cells[column.members[0]]!.pad.bottom
                            return end - column.cut
                        }
                        // (No shorter than the row says, nor than the cells
                        // set whole in it: lab `t32c` (Word for Windows, as
                        // the Mac's print), zh-15728c84 p8's row of 81pt at
                        // least, its centred "每年至少开展（参加）/ 1 次政务公开
                        // 业务培训" two 31.9pt lines and 8.5 after: Word centres
                        // it 4.6pt down a part of 81.3, one line of it 20.5
                        // down; with no stated height the part is that cell's
                        // 72.4 and it stands at the top. Ours centred it in the
                        // 64 its neighbour keeps, which it overfills, and fell
                        // back to the room to the page's foot: 10.5 down.)
                        var whole = 0.0
                        for (n, _) in setWhole {
                            let column = columns[n]
                            let d0 = _cells[column.members[0]]!
                            let last = column.members[column.members.count - 1]
                            whole = max(whole, _tops[last] + _heights[last] - _tops[column.members[0]] + d0.pad.top + d0.pad.bottom)
                        }
                        if let keptMax = kept.max(), case let part = max(keptMax, stated, whole, ghostPart ?? 0), part < avail {
                            for (n, _) in setWhole {
                                let column = columns[n]
                                let d0 = _cells[column.members[0]]!
                                let blockTop = _tops[column.members[0]]
                                let blockBottom = _tops[column.members[column.members.count - 1]] + _heights[column.members[column.members.count - 1]]
                                let room = part - d0.pad.top - d0.pad.bottom - (blockBottom - blockTop)
                                if room >= -0.01 {
                                    setWhole[n] = y + d0.pad.top + max(0, room) * (d0.verticalAlign == "center" ? 0.5 : 1) - blockTop
                                }
                            }
                        }
                    }
                    if stuck, !fresh { moved = false }
                    // (Nor where no cell has anything left for the next
                    // page — every one set whole here, or ended: then only
                    // the row's own height is over, and Word takes the row
                    // over whole. bug59058's yearly rows, one centred line
                    // and 14.4pt after it in each cell, were squeezed into
                    // the 33.8pt left at a page's foot.)
                    // (A cell cut at its last cut — the end of its last
                    // paragraph, space after and all — has only its margin
                    // left, which is nothing to go over.)
                    // (Only for a row of its own: a cell merged down
                    // has the rows below for the rest, and zh-e6d54ae4's
                    // such row parts at the foot as Word parts it.)
                    if moved, !fresh, first, theme.wordRules, columns.indices.allSatisfy({ n in
                        _cells[columns[n].members[0]]!.rowSpan == 1
                    }), !(0 ..< i).reversed().prefix(while: { _cells[$0]?.table == c.table }).contains(where: { m in
                        let d = _cells[m]!
                        return d.row < c.row && d.row + d.rowSpan - 1 >= c.row
                    }), columns.indices.allSatisfy({ n in
                        setWhole[n] != nil || next[n] >= rowBottom - 0.01 || next[n] >= (columns[n].cuts.max() ?? rowBottom) - 0.01
                    }) {
                        moved = false
                    }
                    if let traced = Self.debugRows, traced == page + 1 {
                        FileHandle.standardError.write(Data("after-columns row \(c.row): moved \(moved) stuck \(stuck) cols \(columns.map { "[\($0.members[0]) cut \($0.cut / _px(1)) bottom \($0.bottom / _px(1)) cuts \($0.cuts.map { $0 / _px(1) })]" }) next \(next.map { $0 / _px(1) }) rowBottom \(rowBottom / _px(1)) setWhole \(setWhole.count) avail \(avail / _px(1))\n".utf8))
                    }
                    if !moved {
                        if !fresh, y > 0.01 {
                            // Not a line of it fits here: the row starts the next page.
                            // (Where it opens that page whole, its centred cells
                            // are centred again — see the start moved above.)
                            if first { for n in columns.indices { columns[n].cut = c.rowTop } }
                            newPage()
                            fresh = true
                            if repeats { repeatHeader(of: c.table, before: i) }
                            if c.row > 0 { continueSpans(into: i, c) }
                            // (Under the table's top line there: see `headLift`.)
                            if y < 0.01 { y += headLift(i, j, c) }
                            continue
                        }
                        // (A line taller than a page: placed, and over the foot.)
                        fits = true
                    }
                }
                // (Where the row parts, its part on this page is as tall as
                // the most any cell keeps here and no shorter than the row
                // says it is, and a centred cell's lines stand centred in
                // that part: zh-15728c84's row 9, at least 82.75pt, keeps
                // five 15pt lines of its centred cells on page 3 and Word
                // sets them 3.9pt down in a part of 83.2 — ours at its top.)
                var shift: [Int: Double] = [:]
                var partHeight: Double? = nil
                if theme.wordRules, !fits, first {
                    var extent: [Int: (top: Double, bottom: Double)] = [:]
                    for (n, column) in columns.enumerated() where setWhole[n] == nil {
                        let d0 = _cells[column.members[0]]!
                        // (A cell merged down, parted from its text's top below the row's own
                        // bottom, ends where it is cut: see `partedBelow`.)
                        let partedBelow = theme.wordRules && RichTextTheme.wordWindowsPages && d0.rowSpan > 1 && column.cut > c.rowTop + 0.01 && column.cut >= column.bottom - 0.01
                        let bottom = next[n] >= rowBottom - 0.01 && !partedBelow ? column.bottom + (partPad(column)?.amount ?? 0) : next[n] + d0.pad.bottom
                        let textTop = max(column.cut, _tops[column.members[0]] - d0.pad.top)
                        extent[n] = (textTop, bottom)
                    }
                    // (… and the cells set whole in it: see where they are.)
                    var whole = 0.0
                    for (n, _) in setWhole {
                        let column = columns[n]
                        let d0 = _cells[column.members[0]]!
                        let last = column.members[column.members.count - 1]
                        whole = max(whole, _tops[last] + _heights[last] - _tops[column.members[0]] + d0.pad.top + d0.pad.bottom)
                    }
                    let part = min(avail, max(stated, whole, ghostPart ?? 0, extent.map { n, e in e.bottom - columns[n].cut }.max() ?? 0))
                    // (The rules end with the part only where no cell
                    // merged down from above has text below it: zh-e6d54ae4's
                    // "(二)衡酌實際需求…" runs on beside the row's part to the
                    // page's foot, and the part with it.)
                    let below = (0 ..< i).reversed().prefix(while: { _cells[$0]?.table == c.table }).contains { m in
                        let d = _cells[m]!
                        guard d.row < c.row, d.row + d.rowSpan - 1 >= c.row, _tops[m] + _heights[m] > c.rowTop + part + 0.01 else { return false }
                        // (A centred cell merged down whose whole text fits the rows of it on this page
                        // is centred in them — lab `cm1` — so none of it runs on below the part:
                        // zh-9bcea239's "企业管理（300分）", 100pt of text over eight rows, ends
                        // page 11 in its rows' part, the table's last line 16pt higher than the foot in
                        // Word's print, where ours ran it on to the foot.)
                        if theme.wordRules, RichTextTheme.wordWindowsPages, d.verticalAlign == "center", !d.vertical {
                            var lo = m, hi = m
                            while lo > 0, let e = _cells[lo - 1], e.table == c.table, e.row == d.row, e.column == d.column { lo -= 1 }
                            while hi + 1 < i, let e = _cells[hi + 1], e.table == c.table, e.row == d.row, e.column == d.column { hi += 1 }
                            let text = _tops[hi] + _heights[hi] - _tops[lo] + d.pad.top + d.pad.bottom
                            if text <= c.rowTop + part - d.rowTop + 0.01 { return false }
                        }
                        return true
                    }
                    if !below { partHeight = part }
                    // (Only where the row's own text parts there: a sliver row beside a cell that runs on to the foot is centred
                    // over that cell's reach — zh-64044a1d's.)
                    prevPartBottom = below && theme.wordRules && RichTextTheme.wordWindowsPages
                        && columns.indices.contains(where: { _cells[columns[$0].members[0]]!.rowSpan == 1 && next[$0] < rowBottom - 0.01 }) ? y + part : nil
                    // (A centred cell merged down from the rows above, its text on
                    // this page, is centred in the part of its rows that is on the
                    // page — down to this row's part — not over every row it
                    // covers: zh-1eeb9f9a's "依法行政" over three rows, the third
                    // parting at p10's foot, stands 43pt higher in Word's print.
                    // Lab `cm1`: centred in the first page's portion.)
                    if RichTextTheme.wordWindowsPages, c.row > 0 {
                        var spans: [[Int]] = []
                        var open: (row: Int, column: Int)? = nil
                        var k = i - 1
                        while k >= 0, let d = _cells[k], d.table == c.table {
                            if d.row < c.row, d.row + d.rowSpan > c.row, !d.vertical {
                                if let o = open, o.row == d.row, o.column == d.column { spans[spans.count - 1].insert(k, at: 0) }
                                else { spans.append([k]); open = (d.row, d.column) }
                            } else { open = nil }
                            k -= 1
                        }
                        for members in spans {
                            let d = _cells[members[0]]!, lastM = members[members.count - 1]
                            guard d.verticalAlign == "center" else { continue }
                            let top = _tops[members[0]], bottom = _tops[lastM] + _heights[lastM]
                            var reach = part
                            if below {
                                // (A cell merged from above that runs on to the foot: the part
                                // reaches the last of its lines that stands on the page.)
                                for m in (0 ..< i).reversed().prefix(while: { _cells[$0]?.table == c.table }) {
                                    guard let e = _cells[m], e.row < c.row, e.row + e.rowSpan - 1 >= c.row, !e.vertical,
                                          let last = cellCuts(m).last(where: { $0 <= c.rowTop + avail + 0.01 }) else { continue }
                                    reach = max(reach, last - c.rowTop)
                                }
                            }
                            // (Only where the row is a sliver beside that cell, 30pt or more shorter
                            // than the cell's reach: zh-64044a1d's 18.5pt row. Where the row has
                            // text of its own that parts it, Word centres in the row's part.)
                            let onFoot = below && reach - part >= _px(30)
                            if !onFoot { reach = part }
                            let free = c.rowTop + reach - d.rowTop - d.pad.top - d.pad.bottom - (bottom - top)
                            guard free >= -0.01 else { continue }
                            let onPage = _allPieces.indices.filter { _allPieces[$0].page == page && members.contains(_allPieces[$0].paragraph) && _allPieces[$0].part != .rules && !_allPieces[$0].repeated }
                            guard let first0 = onPage.first else { continue }
                            // (Not text that goes on from the page before: its lines stand where the cut left them, at the
                            // part's head, level with the row's own first line. Lab cm4 and zh-9ba2ead7 p8, whose "房屋及设施
                            // 设备…" block ours moved 36pt up, above the margin.)
                            if theme.wordRules, _allPieces[first0].flowTop > top + 0.01 { continue }
                            // (Where the text stands now, by its piece; where it should stand, by the row's page y.)
                            let nowAt = _allPieces[first0].pageY + (top - _allPieces[first0].flowTop)
                            let wantAt = y + (d.rowTop + d.pad.top + max(0, free) * 0.5 - c.rowTop)
                            // (Only for a cell merged from above that runs on: the other cells keep the
                            // flow's own offset and move up only, as the first lab-checked rule did.)
                            // (… and DOWN to that middle, where the cell's text begins on this page in one piece and
                            // stands above it: zh-5450d509's "监督检查", merged over three rows the last of which parts at
                            // p6's and p7's feet, 23.9 and 16.1pt lower in Word's print, centred over its rows' part down
                            // to the foot; ours, centred over the two whole rows, 23.7 and 15.9 high. Not text that began on
                            // the page before — zh-9ba2ead7's and zh-4d143b5e's stood far off Word's when moved.)
                            let down = theme.wordRules && wantAt - nowAt > 0.5 && onPage.count == 1 && top >= _allPieces[first0].flowTop - 0.01
                            let delta = onFoot || down ? wantAt - nowAt : d.rowTop + d.pad.top + max(0, free) * 0.5 - top
                            guard onFoot || down ? abs(delta) > 0.5 : delta < -0.5 else { continue }
                            guard !onPage.isEmpty, onPage.allSatisfy({ _allPieces[$0].flowBottom <= c.rowTop + reach + 0.01 || _allPieces[$0].flowBottom <= bottom + 0.01 || (onFoot && bottom <= c.rowTop + reach + 0.01) })
                                    || (down && bottom <= c.rowTop + reach + 0.01) else { continue }
                            RuleTrace.hit("word-merged-centred-cell-centres-in-its-part-of-the-page")
                            for n in onPage.reversed() {
                                let old = _allPieces[n]
                                var moved = PagePiece(paragraph: old.paragraph, flowTop: old.flowTop, flowBottom: old.flowBottom, page: old.page, pageY: old.pageY + delta)
                                moved.part = old.part == .all ? .text : old.part
                                var kept: [PagePiece] = []
                                if old.part == .all {
                                    var rules = PagePiece(paragraph: old.paragraph, flowTop: old.flowTop, flowBottom: old.flowBottom, page: old.page, pageY: old.pageY)
                                    rules.part = .rules
                                    kept.append(rules)
                                }
                                _allPieces.replaceSubrange(n ... n, with: kept + [moved])
                                if let at = _pages[old.page].lastIndex(of: old) { _pages[old.page].replaceSubrange(at ... at, with: kept + [moved]) }
                            }
                        }
                    }
                    for (n, e) in extent {
                        let d0 = _cells[columns[n].members[0]]!
                        // (Not a turned cell, whose centring is across it:
                        // zh-f2835e26's tbRlV "创 新 发 展", centred in a row
                        // that parts at p5's foot, starts its indent under the
                        // cell's top in Word for Windows' print, as in a row
                        // whole; ours moved it 92pt down, past the foot.)
                        guard !d0.vertical, d0.verticalAlign == "center" || d0.verticalAlign == "bottom" else { continue }
                        let free = part - (e.bottom - e.top)
                        let want = max(0, free) * (d0.verticalAlign == "center" ? 0.5 : 1)
                        shift[n] = want - (e.top - columns[n].cut)
                    }
                }
                // The rules: from the row's top down to the page's foot,
                // then the row's last stretch with its bottom line.
                // (A first part's rules end with it, not at the page's
                // foot: zh-91e44bcb's "5.要求行政机关确认…", at least
                // 38.95pt, keeps one 31.2pt line on page 4 and Word closes
                // it 40.1 under its top with 16pt of the page left under
                // it — ours ran its sides and its bottom line to the foot.)
                let shown = fits ? rest : partHeight ?? avail
                let from = first && !(fits && rest > c.ownRowHeight + 0.01) ? c.rowTop
                    : fits ? rowBottom - rest : max(c.rowTop + 1, min(rowBottom - rest, rowBottom - avail - 1))
                // (A part that goes over has its top line where a row's own
                // would be, on the page's head, its text a line's width under
                // it: lab `sr` (Word for Windows, zh-291fcea7's package), a
                // row parted at page 1's foot draws its top rule on page 2
                // at 56.88, as a table opening the page does; ours 0.7pt
                // lower, the text's offset and the rule's both.)
                var rule = PagePiece(paragraph: i, flowTop: from - lift, flowBottom: min(rowBottom, from + shown), page: page, pageY: y - lift)
                rule.part = .rules
                rules.append(rule)
                _pages[page].append(rule)
                for (n, column) in columns.enumerated() {
                    if doneWhole.contains(n) { continue }
                    if let at = setWhole[n] {
                        doneWhole.insert(n)
                        for k in column.members {
                            var piece = PagePiece(paragraph: k, flowTop: _tops[k], flowBottom: _tops[k] + _heights[k], page: page, pageY: at + _tops[k])
                            piece.part = .text
                            pieces[k, default: []].append(piece)
                            _pages[page].append(piece)
                        }
                        continue
                    }
                    for k in column.members {
                        // (A turned cell is drawn across its whole cell, not
                        // down its lines: zh-264d7516's "被征地农户人员信息",
                        // merged over nine rows, showed only through its one
                        // line's window, which is to say not at all.)
                        let turned = theme.wordRules && _cells[k]?.vertical == true
                        let top = turned ? _cells[k]!.rowTop : _tops[k]
                        let bottom = turned ? _cells[k]!.rowTop + _cells[k]!.rowHeight : top + _heights[k]
                        let lo = max(top, column.cut), hi = fits ? bottom : min(bottom, next[n])
                        guard hi > lo + 0.01 || (pieces[k] == nil && hi >= lo && bottom <= lo + 0.01) else { continue }
                        // (What goes over stands its cell's top margin under
                        // the rule, as the row's first part did: zh-9c5d0c3f's
                        // road signs, a row of pictures parted at page 5's
                        // foot, go on 5pt lower on page 6 in Word's print
                        // than ours, which had only the rule.)
                        let again = !first && theme.wordRules ? max(0, _cells[column.members[0]]!.pad.top - ruleUnder(c, parted: true)) + nestedRepeat(column) : 0
                        var piece = PagePiece(paragraph: k, flowTop: lo, flowBottom: hi, page: page, pageY: y + (lo - column.cut) + (shift[n] ?? 0) + again + (fits ? ((partPad(column).map { lo >= $0.at - 0.01 ? $0.amount : 0 }) ?? 0) : 0))
                        piece.part = .text
                        pieces[k, default: []].append(piece)
                        _pages[page].append(piece)
                    }
                }
                y += shown
                if fits { break }
                for n in columns.indices { columns[n].cut = next[n] }
                first = false
                newPage()
                fresh = true
                if repeats { repeatHeader(of: c.table, before: i) }
                if c.row > 0 { continueSpans(into: i, c) }
                // (What goes over is ruled across its top again, and its
                // text stands below that rule as the row's did: zh-89385c94's
                // second page, 0.4pt higher than Word's without it.)
                // (Not where every cell of the row says it has no top line:
                // lab `tb` (Word 16 Mac, zh-13552a3a's package), cells of top
                // nil and bottom single, a row parted at page 1's foot opens
                // page 2 with no line and its text at the margin, where with
                // a top line stated the line is drawn there and the text
                // stands its 0.48 lower. zh-13552a3a's parted rows opened
                // their pages 0.8pt low, and p28's last line went over.)
                // (At the page's head, with no header row over it, a cell
                // that states no top line of its own opens under the table's
                // top line, as the table's edge there: zh-cec9d337's
                // assignments table, a 3pt thinThickSmallGap top over
                // half-point inside lines, opens p25 and p26 under the
                // compound line in Word's print, where the row going on has
                // a cell of no top line, its text 4pt lower than ours; p20
                // to p24, whose rows' cells all state theirs, open under
                // their half-point line as ours.)
                if theme.wordRules {
                    lift = Self._rowOpensBare(i, j, document) ? 0 : ruleUnder(c, parted: true)
                    if lift > 0, !repeats { lift = max(lift, lift + headLift(i, j, c)) }
                    y += lift
                }
                // (The notes marked in what this page will hold of the row.)
                if theme.wordRules, !rowPending.isEmpty {
                    let width = noteWidth()
                    var here: [Int] = []
                    var room = 0.0
                    for id in rowPending {
                        guard let k = (i ..< j).first(where: { _footnotes(in: $0, document).contains(id) }),
                              let n = columns.firstIndex(where: { $0.members.contains(k) }),
                              let mark = _footnoteMarkLine(k, id, document), let note = _note(id, width: width, document) else { here.append(id); continue }
                        room += note.height + (pageNotes.isEmpty && here.isEmpty ? _note(-1, width: width, document)?.height ?? 0 : 0)
                        if y + (mark.bottom - columns[n].cut) + room > contentH + 0.01 { break }
                        here.append(id)
                    }
                    rowPending.removeAll { here.contains($0) }
                    reserveNotes(here)
                }
            }
            // (In paragraph order, the rules after their paragraph's text.)
            for k in i ..< j {
                _allPieces.append(contentsOf: pieces[k] ?? [])
                if k == i { _allPieces.append(contentsOf: rules) }
            }
            return true
        }
        // (A table placed against the page, down from the text above it, whose last row
        // ends past the margin does not take the page's end with it: the paragraph after
        // it is its anchor, and stands where the flow stood, over the table — zh-0b87285b's
        // title, a 29pt line at 90, over a table 126.8pt down that ends past a 451pt
        // margin, is on the table's page in Word's print; ours took it to a page of its own.)
        func tableEndsOverAnchor(_ c: _CellGeo, _ j: Int) -> Bool {
            theme.wordRules && RichTextTheme.wordWindowsPages && j < count && _cells[j] == nil
                && tableReturn.map { $0.table == c.table && $0.page == page && $0.y + _heights[j] <= $0.top + 0.01 } == true
        }
        func placeDeferred() {
            for piece in deferredUnder {
                let h = piece.flowBottom - piece.flowTop
                if y + h > contentH + 0.01, y > 0.01 { newPage() }
                let again = PagePiece(paragraph: piece.paragraph, flowTop: piece.flowTop, flowBottom: piece.flowBottom, page: page, pageY: y)
                _pages[page].append(again)
                let at = _allPieces.firstIndex(where: { $0.paragraph > piece.paragraph }) ?? _allPieces.count
                _allPieces.insert(again, at: at)
                y += h
            }
            deferredUnder = []
        }
        while i < count {
            var sectionBreakHandled = false
            // An odd/even section may begin with a table, so enforce its
            // side before either the table-row or paragraph path. Word's
            // zh-291fcea7 leaves page 8 completely blank before its form.
            // A stated numbering restart instead rounds that first number
            // up to the requested side; it does not itself add a page.
            if theme.wordRules, resumeCursor == nil, i > 0, i < _sectionOf.count,
               _sectionOf[i] != _sectionOf[i - 1],
               let parity = _setup(ofParagraph: i).sectionStartParity {
                if y > 0.01 || !_pages[page].isEmpty || markOnPage { newPage() }
                while page % _columns != 0 { newPage() }
                if document.paragraphs[i].style.pageBreakTwice { newPage() }
                let physical = page / _columns
                if physical > 0, _sectionNumberStart(_sectionOf[i], document) == nil,
                   (_pageNumberOf(physical - 1, document) + 1) % 2 != parity.rawValue {
                    _blankPages.insert(physical)
                    _numberedBlankPages.insert(physical)
                    repeat { newPage() } while page % _columns != 0
                }
                // A page-anchored table can move y down before the row's
                // break check. That offset is not content before this
                // section: its already-handled break must not fire again.
                sectionBreakHandled = true
            }
            // (Under the table they were moved below, once it has ended.)
            if !deferredUnder.isEmpty, _cells[i]?.table != deferredTable { placeDeferred() }
            // (After a table placed further down the page, the text goes on
            // from where it stood, the table a band it keeps clear of:
            // zh-10eab555's issuing line, a table 702.9pt down page 2, has
            // the contents' title and lines over it in Word's print, down
            // to 677; ours set them under it, on page 3.)
            if let back = tableReturn, _cells[i]?.table != back.table {
                tableReturn = nil
                if back.page == page, y > back.top {
                    // (No band for a table wholly outside the text's width — in
                    // the margin beside it: tdf92157's address block, 467.9pt
                    // from the page's edge against a text area ending at 454.4,
                    // leaves the letter's table at its place in Word's print.)
                    let left = _tableLeft(back.table, document)
                    let beside = theme.wordRules && (left >= (_tableFlowWidth[back.table] ?? width) - 0.01
                        || left + (_columnWidths[back.table] ?? []).reduce(0, +) <= 0.01)
                    if !beside { tableBands.append((top: back.top, bottom: y, owner: -1)) }
                    y = back.y
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
            if let beside = besideTable {
                let p = document.paragraphs[i]
                if beside.page != page || y >= beside.bottom - 0.01 { besideTable = nil }
                else if let c = _cells[i], i > 0, _cells[i - 1] == nil, blank(document.paragraphs[i - 1]), let ts = document.tableStyles[c.table], ts.floatsOverText, ts.floatRaiseY != nil || ts.floatOffsetY != nil, ts.keptPosition != nil, theme.wordRules, RichTextTheme.wordWindowsPages, ts.keptPosition?.containsSubstring("tblOverlap w:val=\"never\"") != true {
                    // (A floating table whose anchor stood beside the one above is set from there: lo-e998b55c.)
                    RuleTrace.hit("floating-table-set-from-an-anchor-beside-the-float-above")
                    besideTable = nil
                }
                else if (_cells[i] != nil && !(_cells[i].map { _narrowBesideFloat($0.table, document) } ?? false)) || (_cells[i] == nil && !(blank(p) || (i < _besideLead.count && _besideLead[i] > 0))) { y = beside.bottom; besideTable = nil }
            }
            // (A table floating in the left margin, wholly outside the text's width, takes no room of
            // the text's: the paragraph after it stands at its top, beside it. Word for Windows' print of
            // LibreOffice's floattable-anchorpos: "D" at 290 beside "C"'s table, 76pt wide and 98pt left of
            // the text; ours set it under the table, at 413.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, besideTable == nil, i > 0, _cells[i] == nil, !blank(document.paragraphs[i]),
               _cells[i - 1] != nil {
                // (Over the tables just before it — a page-anchored one between does not stand in the way.)
                var seen: Set<String> = []
                var j = i - 1
                while j >= 0, let d = _cells[j] { seen.insert(d.table); j -= 1 }
                for prev in seen {
                    guard let ts = document.tableStyles[prev], ts.floatsOverText, !ts.pageAnchored, ts.keptPosition != nil,
                          _tableLeft(prev, document) + (_columnWidths[prev] ?? []).reduce(0, +) <= 0.01,
                          let top = _pages[page].filter({ _cells[$0.paragraph]?.table == prev }).map(\.pageY).min(), top < y - 0.01 else { continue }
                    y = top
                    break
                }
            }
            // (An ordinary table straight after a floating one that keeps text off (tblOverlap never), fitting in the
            // room at its right, starts level with it and stands beside it — `_besideWideFloatShift` sets it across:
            // Word's print of LibreOffice's lo-ce0d5e6d, two 387pt tables side by side on one page, ours one under the
            // other and over onto a second.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, besideTable == nil, i > 0, let c = _cells[i], let prev = _cells[i - 1]?.table,
               prev != c.table, _tableFirstParagraph[c.table] == i, _besideWideFloatShift(c.table, document) != nil,
               let top = _pages[page].filter({ _cells[$0.paragraph]?.table == prev && !$0.repeated }).map(\.pageY).min(), top < y - 0.01 {
                RuleTrace.hit("word-table-after-a-float-stands-beside-it-where-it-fits")
                besideTable = (y, page)
                y = top
            }
            // (A table as wide as the text leaves no strip: what follows goes under
            // it, not up at its anchor — 6e6d8e9e's blank lines after its sections.)
            if theme.wordRules, besideTable == nil, i > 0, _cells[i] == nil, let prev = _cells[i - 1]?.table,
               !(_floatLeavesNoStrip(prev, i, document) && _floatFollowsFloat(prev, document)),
               blank(document.paragraphs[i]) || (i < _besideLead.count && _besideLead[i] > 0) || _splitMarginFloatBeside(prev, i, page, document),
               let ts = document.tableStyles[prev], ts.floatOffsetY != nil || (ts.floatRaiseY != nil && _markBesideOffsetFloat(prev, i, document)) || (i < _besideLead.count && _besideLead[i] > 0) || _anchorBesideLeftTable(prev, i, document) || _splitMarginFloatBeside(prev, i, page, document), !ts.pageAnchored, ts.keptPosition != nil,
               (i < _besideLead.count && _besideLead[i] > 0) || _splitMarginFloatBeside(prev, i, page, document) || _tableLeft(prev, document) - _px(9) - _px(_setup(ofParagraph: i).headerWrapLeft) >= _px(18) || _stripBesideLeftTable(prev, i, document) || _anchorBesideLeftTable(prev, i, document) || _markBesideOffsetFloat(prev, i, document),
               case let firstPage = _beside_firstPage(of: prev, upTo: page, text: i < _besideLead.count && _besideLead[i] > 0 && !blank(document.paragraphs[i])),
               // (… but only where the text does not fit whole beside those rows and goes on
               // over the page: a line or a few that fit stand on the table's last page, as in
               // Word's print of LibreOffice's lo-9cc5d6ef "AB" and lo-eba386b0.)
               case let startPage = firstPage == page - 1 && i < _heights.count
                   && ((_pages[firstPage].contains(where: { _cells[$0.paragraph] == nil })
                       && _heights[i] > contentH - (_pages[firstPage].filter({ _cells[$0.paragraph]?.table == prev && !$0.repeated }).map(\.pageY).min() ?? 0) + 0.01)
                       // (Nor where the table has nothing on this page: its last row ended past the first
                       // page's foot and the page opened after it is empty of it. lo-853c06a0, two 91pt rows
                       // on a 166pt page: "Anchor paragraph." stands beside A1 on page 1 in Word's print.)
                       || (theme.wordRules && RichTextTheme.wordWindowsPages && !_pages[page].contains(where: { _cells[$0.paragraph]?.table == prev }))) ? firstPage : page,
               let top = _pages[startPage].filter({ _cells[$0.paragraph]?.table == prev && (startPage == page || !$0.repeated) }).map(\.pageY).min(), top < y - 0.01 || startPage < page {
                // (Text beside a table whose rows run over two pages starts on
                // the page of its FIRST rows, level with the table's top: Word's
                // print of LibreOffice's floattable-wrap-on-all-pages. It goes on
                // from there to the next page, beside the rest of the table.)
                if startPage < page { RuleTrace.hit("text-beside-a-split-floating-table-starts-on-its-first-page") }
                besideTable = (y, page)
                page = startPage
                y = top
                // From the line the table hangs from, where its first row
                // is on this page: its tblpY stands it lower than that,
                // and Word's first empty line beside zh-6e6b9821's table
                // is that 8pt above the table's top.
                var first = i - 1
                while first > 0, _cells[first - 1]?.table == prev { first -= 1 }
                if _pages[page].contains(where: { $0.paragraph == first }), let down = ts.floatOffsetY {
                    y = max(_pages[page].map(\.pageY).min() ?? 0, top - _px(down))
                }
                // (A line the table hangs from, after a paragraph framed against the page whose top stands
                // inside the first line's place and whose foot is over the table's top, stands 4.9pt under
                // the frame's top, not at the margin: Word for Windows' labs b88 (lo-88b29958), the text
                // paragraph's baseline 176.7 / 187.0 / 196.7 for frames at 75 / 85.25 / 95pt, and none for
                // a frame above the margin (50), or one reaching the table (107.5).)
                if theme.wordRules, RichTextTheme.wordWindowsPages, first > 0, _cells[first - 1] == nil, first - 1 < _heights.count,
                   case let fp = document.paragraphs[first - 1], fp.cell == nil, let frame = fp.style.frame,
                   frame.verticalAnchor == "page", frame.horizontalAnchor == "page", frame.verticalAlign == nil,
                   _pages[page].contains(where: { $0.paragraph == first }) {
                    let marginTop = _pxMarginTop(page)
                    let frameTop = _px(frame.y) - marginTop
                    if frameTop >= -0.01, frameTop < _heights[first] - 0.01 || frameTop < _px(47), frameTop + _heights[first - 1] <= top + 0.01 {
                        RuleTrace.hit("word-line-after-a-page-framed-paragraph-stands-under-the-frames-top")
                        y = max(y, frameTop + _px(4.9 + 5.35))
                    }
                }
                // (An anchor beside a float that is raised stands one line under the
                // line that float hangs from: its own table is 12.9pt under the
                // first's top in Word's print of lo-e998b55c, not level with it.)
                if ts.floatOffsetY == nil, first > 0, first - 1 < _heights.count, _anchorBesideLeftTable(prev, i, document) {
                    y = top + _px(ts.floatRaiseY ?? 0) + _heights[first - 1]
                }
                // (A table held above where the text before it ends: what follows goes on from
                // that end, beside the table still. lo-f48e444e's second paragraph at 170.2,
                // under the first's four lines, in Word's print.)
                if let pf = pinnedFrom, pf.table == prev, pf.page == page { y = max(y, pf.y) }
            }
            // Converged: this paragraph starts on the same page at the same
            // y as before and nothing below has changed, so the old pieces
            // and pages from here on are still right.
            if restarted, !reordered, i > settled, resumeCursor == nil, oldStart.count == count + 1,
               oldStart[i] < oldPieces.count, case let old = oldPieces[oldStart[i]],
               old.page == page, abs(old.pageY - y) < 0.01, abs(old.flowTop - _tops[i]) < 0.01,
               page < oldPages.count {
                _allPieces.append(contentsOf: oldPieces[oldStart[i]...])
                _pages[page].append(contentsOf: oldPages[page].filter { $0.paragraph >= i })
                if page + 1 < oldPages.count { _pages.append(contentsOf: oldPages[(page + 1)...]) }
                // (The pages taken back keep their pinned floats.)
                for (id, kept) in shelvedPins where kept.pin.page >= page && _pinnedFloats[id] == nil {
                    _pinnedFloats[id] = kept.pin
                    _floatShiftY[id] = kept.shift
                }
                if notesOn {
                    pageNotes = oldNotes[page] ?? pageNotes
                    for (k, v) in oldNotes where k > page { _pageNotes[k] = v }
                    for (k, v) in oldCuts where k >= page { _noteCutOut[k] = v }
                    for (k, v) in oldCarries where k > page { _noteCarryIn[k] = v }
                    pageCut = nil
                }
                break
            }
            if notesOn {
                var end = i + 1
                if let c = _cells[i] { while end < count, let d = _cells[end], d.table == c.table, d.row == c.row { end += 1 } }
                if placingRange != i ..< end {
                    if !rowPending.isEmpty { reserveNotes(rowPending); rowPending = [] }
                    placingRange = i ..< end
                    placing = placingRange.flatMap { _footnotes(in: $0, document) }
                }
                if _cells[i] == nil, document.paragraphs[i].style.keepNext {
                    for id in placing where !pendingNotes.contains(id) && !pageNotes.contains(id) { pendingNotes.append(id) }
                } else if pendingNotes.isEmpty {
                    // (A body paragraph's note is set on this page only
                    // with the line that marks it: one whose line goes over
                    // goes with it — see `newPage`. zh-424775e4's page 9
                    // keeps three lines of the paragraph whose fourth marks
                    // footnote 2, which stands on page 10 in Word's print.)
                    if theme.wordRules, _cells[i] == nil, placing.count > 0 {
                        var here: [Int] = []
                        var room = 0.0
                        let width = noteWidth()
                        for id in placing where !pageNotes.contains(id) {
                            guard var mark = _footnoteMarkLine(i, id, document), let note = _note(id, width: width, document) else { here.append(id); continue }
                            // (On a page of columns the mark's line is the whole line it
                            // stands in, a raised mark's box ending above its foot.)
                            if slotNotes {
                                let g = geometry(i)
                                if let lb = Self._lineBottoms(g.painter).map({ $0 + g.textTop }).first(where: { $0 >= mark.bottom - 0.5 }) { mark.bottom = max(mark.bottom, lb) }
                            }
                            room += note.height + (pageNotes.isEmpty && here.isEmpty ? _note(-1, width: width, document)?.height ?? 0 : 0)
                            if y + (mark.bottom - _tops[i]) + room > contentH + 0.01 {
                                // (Unless what is left under the mark's line
                                // holds a line of it or more: the note parts
                                // there, the rest first at the next page's
                                // foot. zh-344a8d08's footnote 3, three lines
                                // marked in page 4's last, has two there in
                                // Word's print and the third on page 5; ours
                                // took the mark's line over with it, and the
                                // line before, two lines short a page.)
                                let left = contentH - (y + (mark.bottom - _tops[i])) - (room - note.height)
                                if pageCut == nil, let keep = _noteCuts(id, width: width, document).last(where: { $0 <= left + 0.01 }) {
                                    pageCut = (id, keep)
                                    here.append(id)
                                    if slotNotes { cutEnds = y + (mark.bottom - _tops[i]) }
                                    // (A note that parts leaves the foot of the next page to its rest, and a later note
                                    // cannot begin there: the line marking the next one,
                                    // when it stands below this mark's, goes over with
                                    // it. xd e50792c2's footnote 7 parts pages 13/14 in
                                    // Word's print and the lines marking 8 open page 14;
                                    // ours kept them and set 8 first on page 14, a page
                                    // short in all.)
                                    if theme.wordRules, !slotNotes, let next = placing.first(where: { !here.contains($0) && !pageNotes.contains($0) }),
                                       let m2 = _footnoteMarkLine(i, next, document), m2.top > mark.top + 0.5 {
                                        contentH = max(1, min(contentH, y + (m2.bottom - _tops[i]) + room - note.height + keep))
                                    }
                                } else if mark.top > _tops[i] + 0.5 || y > 0.01 {
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
                                    contentH = max(1, min(contentH, y + (mark.top - _tops[i]) + (here.isEmpty ? 0 : room - note.height)))
                                }
                                for later in placing where !here.contains(later) && !pageNotes.contains(later) && !pendingNotes.contains(later) { pendingNotes.append(later) }
                                break
                            }
                            here.append(id)
                        }
                        reserveNotes(here)
                        if let end = cutEnds { contentH = max(1, min(contentH, end + 0.5)); cutEnds = nil }
                    } else if theme.wordRules, let c0 = _cells[i], placing.count > 0 {
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
                        let width = noteWidth()
                        for id in placing where !pageNotes.contains(id) {
                            guard rowPending.isEmpty, let k = placingRange.first(where: { _footnotes(in: $0, document).contains(id) }),
                                  let mark = _footnoteMarkLine(k, id, document), let note = _note(id, width: width, document) else {
                                if rowPending.isEmpty { here.append(id) } else { rowPending.append(id) }
                                continue
                            }
                            room += note.height + (pageNotes.isEmpty && here.isEmpty ? _note(-1, width: width, document)?.height ?? 0 : 0)
                            if y + (mark.bottom - c0.rowTop) + room > contentH + 0.01 {
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
                                let left = contentH - (y + (mark.bottom - c0.rowTop)) - (room - note.height)
                                if pageCut == nil, let keep = _noteCuts(id, width: width, document).last(where: { $0 <= left + 0.01 }) {
                                    pageCut = (id, keep)
                                    here.append(id)
                                } else {
                                    if y > 0.01 || mark.top > c0.rowTop + 0.5 {
                                        contentH = max(1, min(contentH, y + (mark.top - c0.rowTop) + (here.isEmpty ? 0 : room - note.height)))
                                    }
                                    rowPending.append(id)
                                }
                                for later in placing where !here.contains(later) && !pageNotes.contains(later) && !rowPending.contains(later) { rowPending.append(later) }
                                break
                            }
                            here.append(id)
                        }
                        reserveNotes(here)
                    } else {
                        reserveNotes(placing)
                    }
                } else {
                    var ids = pendingNotes
                    pendingNotes = []
                    for id in placing where !ids.contains(id) { ids.append(id) }
                    reserveNotes(ids, deferring: true)
                }
            }
            // (A table that asks for the body's foot, `w:tblpYSpec="bottom"`:
            // its foot at the body's, as its offset from the page's top.
            // LibreOffice's floattable-from-bottom has it 621pt down a 792pt
            // page in Word's print, margin at 720; ours stood it at the top.)
            func bottomAlignedOffset(_ c: _CellGeo, _ i: Int) -> Double? {
                guard theme.wordRules, document.tableStyles[c.table]?.bottomAligned == true else { return nil }
                var bottom = c.rowTop + c.ownRowHeight, k = i
                while k < count, let d = _cells[k], d.table == c.table { bottom = max(bottom, d.rowTop + d.ownRowHeight); k += 1 }
                let height = bottom - c.rowTop
                guard height < contentH else { return nil }
                let physical = page / _columns
                let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
                // (A hair short of the foot: a table that ends on it opens a page.)
                return (contentH - height - 0.5 + insetTop) / _px(1)
            }
            func raiseAtHead(_ c: _CellGeo) {
                // (At the head too under nothing but what takes no room in
                // Word's flow: frames, and tables floating by the text.
                // zh-76700e5f's ICS/CCS table comes after the cover's
                // floating "3311" table and two frames, and stands at
                // 34.5 in Word's print; ours set it under the "3311"
                // table, at 177.7.)
                let floatsOnly = !_pages[page].isEmpty && _pages[page].allSatisfy { piece in
                    let q = document.paragraphs[piece.paragraph]
                    if let d = _cells[piece.paragraph] { return d.table != c.table && document.tableStyles[d.table]?.floatsOverText == true }
                    return q.style.frameXML != nil
                }
                guard theme.wordRules, c.row == 0, c.firstInRow, i == 0 || _cells[i - 1]?.table != c.table,
                      let up = document.tableStyles[c.table]?.floatRaiseY, y < 0.01 || floatsOnly else { return }
                let physical = page / _columns
                let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
                y = max(-insetTop, -_px(up))
            }
            // (A table floating by the text that opens a page and has more rows than the body holds is
            // lifted, not parted where the body ends: Word sets as many of its whole rows as the page, from
            // its top edge, holds so that the last ends at the body's foot, the top of the first over the
            // margin. LibreOffice's floattable-footer-object, 55pt rows, a body 209pt high under a footer
            // picture: five rows a page, the first at 6.2pt down a page, the fifth ending at the foot.)
            func liftToFoot(_ c: _CellGeo) {
                guard theme.wordRules, RichTextTheme.wordWindowsPages, c.firstInRow, _pages[page].isEmpty,
                      let ts = document.tableStyles[c.table], ts.floatsOverText, !ts.pageAnchored, y < _px(1) + 0.01 else { return }
                let physical = page / _columns
                guard let footer = _headerFooter(.footer, page: physical, document, pageCount: 1),
                      _footerPictureEnd(footer, pageSetup(forPage: physical)) != nil else { return }
                let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
                var heights: [Double] = [], seen = Set<Int>(), k = i
                while k < count, let d = _cells[k], d.table == c.table {
                    if d.row >= c.row, seen.insert(d.row).inserted { heights.append(d.ownRowHeight) }
                    k += 1
                }
                let all = heights.reduce(0, +)
                guard all > contentH - y + 0.01 else { return }
                var run = 0.0, n = 0
                for h in heights { if run + h <= contentH + insetTop + 0.01 { run += h; n += 1 } else { break } }
                guard n >= 2, run > contentH - y + 0.01 else { return }
                RuleTrace.hit("floating-table-lifted-to-end-at-the-foot")
                y = contentH - run - ruleUnder(c)
            }
            if let c = _cells[i] {
                // (Where the row opens the page, a break it states is no
                // break, whatever offset the table is then set down by:
                // LibreOffice's tdf115883, a table placed 0.05pt under its
                // page's margin with w:pageBreakBefore in its first cell,
                // is the document's first page in Word's print; ours began
                // with a blank one.)
                let rowOpensThePage = y < 0.01 && _pages[page].isEmpty && !(theme.wordRules && markOnPage)
                // A table every row of which is marked a header (see
                // `headerRows`) starts on a page of its own where it does
                // not fit the rest of this one: zh-8628cfbe's annex 3, 28
                // rows all marked, after its heading at the top of page 30,
                // opens page 31 in Word's print, the heading alone on 30;
                // ours set it under the heading and ran a page short. Lab
                // `ah` (Word 16 Mac): the marks taken off, it stays under
                // the heading; a pageBreakBefore for the in-paragraph break
                // changes nothing. (From 2013's layout: zh-e37f8d40's forms,
                // 16 rows all marked, mode 14, stay under their headings.)
                if theme.wordRules, (document.compatibilityMode ?? 12) >= 15,
                   c.row == 0, c.firstInRow, i == 0 || _cells[i - 1]?.table != c.table, y > 0.01,
                   let ts = document.tableStyles[c.table], ts.headerRow, ts.headerRowCount > (_tableRows[c.table] ?? 0),
                   document.tableStyles[c.table]?.floatX == nil {
                    var last = i
                    while last + 1 < count, _cells[last + 1]?.table == c.table { last += 1 }
                    if last < _tops.count, _tops[last] + _heights[last] - _tops[i] > contentH - y { newPage() }
                }
                // (So does one whose header rows, the ones marked, are
                // taller together than a page, which nothing could part:
                // tdf88496's eight, 702.5pt on a 700.2pt page, after a
                // paragraph at the head of page 1, open page 2 in Word's
                // print, the paragraph alone on 1; ours stood the table
                // under it and ran a page long.)
                if theme.wordRules, (document.compatibilityMode ?? 12) >= 15,
                   c.row == 0, c.firstInRow, i == 0 || _cells[i - 1]?.table != c.table, y > 0.01,
                   let ts = document.tableStyles[c.table], ts.headerRow, ts.headerRowCount > 0,
                   ts.headerRowCount <= (_tableRows[c.table] ?? 0), ts.floatX == nil {
                    var last = i
                    while last + 1 < count, let d = _cells[last + 1], d.table == c.table, d.row < ts.headerRowCount { last += 1 }
                    // (The rows' own heights: a row's cells are paragraphs whose
                    // text may be short of it.)
                    var bottom = 0.0
                    for k in i ... last { if let d = _cells[k] { bottom = max(bottom, d.rowTop + d.rowHeight) } }
                    let block = bottom - c.rowTop
                    if block > contentH - y { RuleTrace.hit("header-block-over-rest") }
                    if block > contentH + 0.01 {
                        RuleTrace.hit("header-block-over-page")
                        newPage()
                    }
                }
                // A table floating by the text straight after another that does,
                // at an offset no higher than the first's, avoids it: it stands
                // 21.5pt lower than the first's foot puts it — lab fs1 (Word for
                // Windows, LibreOffice's floattable-tables-lost): Outer table 2 is
                // 115.34pt under Table 1's text with Table 1's row 91.5pt, 73.82
                // with 50, 30.48 more with a second row of 30; ours 92.5 (the
                // constant is one witness's, not a distance the file states).
                if theme.wordRules, RichTextTheme.wordWindowsPages, c.row == 0, c.firstInRow, i > 0, let before = _cells[i - 1],
                   before.table != c.table, let first = document.tableStyles[before.table], first.floatsOverText, !first.pageAnchored,
                   let second = document.tableStyles[c.table], second.floatsOverText, !second.pageAnchored {
                    let firstAt: Double = (first.floatOffsetY ?? 0) - (first.floatRaiseY ?? 0)
                    let secondAt: Double = (second.floatOffsetY ?? 0) - (second.floatRaiseY ?? 0)
                    // (Labs flt2 and ovl2 autow: the step is taken only when BOTH tables
                    // are auto-width. Two tables that state a width sit level (flt2), and
                    // so does an auto-width second one after a first that states its width:
                    // T10 to T11 is 172pt in Word's print, ours 192 with the step.)
                    if secondAt >= firstAt, second.width == nil, second.widthPercent == nil, first.width == nil, first.widthPercent == nil { y += _px(21.5) }
                }
                // A floating table anchored to the text stands its offset
                // below the text's place (zh-64044a1d's equipment list,
                // 4.35pt under the line before it in Word's print).
                if theme.wordRules, c.row == 0, c.firstInRow, i == 0 || _cells[i - 1]?.table != c.table,
                   let down = document.tableStyles[c.table]?.floatOffsetY {
                    // (Where the offset leaves it no room on this page, it
                    // stands that offset down the next: zh-ad1e59ac's form,
                    // tblpY 205 twips under an empty line that ends page 9,
                    // has its top rule 10.3pt under page 10's margin in
                    // Word's print; ours parted its first row at page 9's
                    // foot and set the rest at page 10's margin.)
                    // (Word for Windows keeps it with its anchor, the
                    // paragraph after the table, while that fits: zh-5a9a85c6's
                    // roster, tblpY 881 under its title on page 18, has its
                    // first row 3.9pt past the margin there in Word's print and
                    // the rest on page 19; ours took it all over.)
                    var anchorFits = false
                    if RichTextTheme.wordWindowsPages {
                        var k = i
                        while k < count, _cells[k]?.table == c.table { k += 1 }
                        anchorFits = k < count && k < _heights.count && _cells[k] == nil && !_pageBreak[k]
                            && y + _heights[k] <= contentH + 0.01
                    }
                    if y > 0.01, y + _px(down) > contentH - 0.01 {
                        if anchorFits { keptPastFoot = c.table } else { newPage() }
                    } else if theme.wordRules, RichTextTheme.wordWindowsPages, y > 0.01, anchorFits, c.ownRowHeight > contentH - y - _px(down) + 0.01,
                              y + _px(down) >= _floatFootLimit(i, page: page, document) {
                        // (Word for Windows sets a floating table's top no lower than the footer's place, the footer
                        // distance and one empty line up from the page's foot: lab ovl2 autow's T34, tblpY 37 twips under
                        // a line ending at 794.7, 17.7pt past that limit, goes whole to the next page in Word's print;
                        // ours parted its first row at the foot.)
                        newPage()
                    } else if theme.wordRules, RichTextTheme.wordWindowsPages, _columns > 1, y > 0.01, i < _sectionOf.count,
                              _columnsOf(paragraph: i) > 1 {
                        // (In a section of columns Word keeps a floating table whole: where
                        // the table, at its offset under the anchor, would run past the
                        // column's foot by more than a few points, the anchor and the table
                        // go to the next column together. Lab fm2 of lo-20f5d558: a 95pt
                        // table at tblpY 472 twips moves from column 2 of page 1 to the top
                        // of page 2's column 1; one that overruns by 3.6pt stays.)
                        var tops = Double.infinity, bottoms = 0.0, k = i
                        while k < count, let d = _cells[k], d.table == c.table {
                            tops = min(tops, d.rowTop); bottoms = max(bottoms, d.rowTop + d.ownRowHeight); k += 1
                        }
                        if bottoms > tops, y + _px(down) + (bottoms - tops) > contentH + _px(4) {
                            RuleTrace.hit("floating-table-in-columns-goes-whole-to-the-next-column")
                            newPage()
                        }
                    }
                    // (A run of floating tables hangs from one anchor, the
                    // paragraph after the run: each stands its own offset
                    // below that place, not below the one before it —
                    // floating-tables-anchor, in Word's print.)
                    if theme.wordRules, RichTextTheme.wordWindowsPages, i > 0, let prevT = _cells[i - 1]?.table,
                       let fb = floatRunBase, fb.table == prevT, fb.page == page,
                       document.tableStyles[prevT]?.floatOffsetY != nil, document.tableStyles[prevT]?.pageAnchored != true {
                        y = fb.y
                    }
                    // (Held where it stood before the text above it wrapped beside it: see `_floatPin`.)
                    if let pin = _floatPin[c.table], pin.page == page, pin.y < y - 0.01 {
                        RuleTrace.hit("word-float-keeps-its-place-when-the-text-before-it-wraps-beside-it")
                        pinnedFrom = (c.table, page, y)
                        y = pin.y
                    }
                    floatRunBase = (c.table, page, y)
                    textFloatTop = (c.table, page, y, _px(down), false)
                    besideChainEnd = nil
                    if RichTextTheme.wordWindowsPages, document.tableStyles[c.table]?.keptPosition?.containsSubstring("w:tblpXSpec=\"right\"") == true {
                        var lo = Double.infinity, hi = -Double.infinity, k = i
                        while k < count, let d = _cells[k], d.table == c.table { lo = min(lo, d.rowTop); hi = max(hi, d.rowTop + d.ownRowHeight); k += 1 }
                        if hi > lo { besideChainEnd = y + _px(down) + (hi - lo) }
                    }
                    // (A table that is the document's first block and holds a
                    // drawing outside its cell is measured from the page's top
                    // edge: LibreOffice's missing-path and tdf78727, tblpY 416
                    // twips, have their drawing 20.8pt down the paper in Word's
                    // print, 70pt over the margin where ours put it. One with
                    // text only, do-not-break-wrapped-tables, stands at the
                    // margin.)
                    if RichTextTheme.wordWindowsPages, i == 0, page == 0, y < 0.01, _pages[page].isEmpty,
                       document.tableStyles[c.table]?.shapesLeaveCell == true {
                        let insetTop = _pageInsetTop.isEmpty ? 0 : _pageInsetTop[0]
                        y = _px(down) - insetTop
                    } else if RichTextTheme.wordWindowsPages, i > 0, _cells[i - 1] == nil, document.paragraphs[i - 1].text.isEmpty,
                              document.paragraphs[i - 1].image == nil, document.paragraphs[i - 1].style.frameXML == nil,
                              i == 1, page == 0, let before = _pages[page].last, before.paragraph == 0, before.pageY <= y + 0.01,
                              !{ () -> Bool in
                                  // (Not where another floating table follows at once: the anchor of both is the paragraph after
                                  // them, which stands under that empty line. LibreOffice's tdf97090, tblpY 941 and -36: the
                                  // first table 47pt under the paragraph after, 126 on the page, ours 103.)
                                  var k = i
                                  while k < count, let d = _cells[k], d.table == c.table { k += 1 }
                                  guard theme.wordRules, k < count, let n = _cells[k], n.table != c.table, let ns = document.tableStyles[n.table] else { return false }
                                  return ns.floatsOverText && ns.floatRaiseY != nil
                              }() {
                        // (An empty first paragraph of the document, just before
                        // the table, is its anchor, and the offset is from that
                        // line's top, not from under it: LibreOffice's
                        // floattable-deleted-anchor, tblpY 1441 under an empty line
                        // at the margin, has its text 72pt under the margin in
                        // Word's print, and shape-in-floattable's drawing 27.65pt
                        // under it. Never above the table's place in the flow:
                        // tdf87460 and floattable-negative-height, tblpY 1 and 9
                        // twips, stand under the line.)
                        y = max(y, before.pageY + _px(down))
                    } else if RichTextTheme.wordWindowsPages, (document.compatibilityMode ?? 12) >= 15, i > 0, _cells[i - 1] == nil,
                              let last = lastEmptyAt, last.i == i - 1, last.page == page, last.y < y - 0.01, y + _px(down) + c.ownRowHeight > contentH + 0.01, last.y + _px(down) + c.ownRowHeight <= contentH + 0.01, Self._tableBeforeEmptiesIsOn(page: page, i: i, cells: _cells, pieces: _pages[page]),
                              Self._followsFloatingTable(i, c.table, document: document, cells: _cells) {
                        // (Compat 15, a table floating after another with empty lines between: it hangs
                        // from the empty line just before it, 45pt under that line's baseline, not
                        // from where the flow has got to. Lab anchor, Word for Windows.)
                        RuleTrace.hit("compat15-second-floating-table-hangs-from-the-empty-line-before-it")
                        y = last.y + _px(down)
                    } else {
                        y += _px(down)
                    }
                }
                // (And one placed above the text's place, at a page's head,
                // that much up into the top margin: zh-76700e5f's cover table,
                // tblpY -733 under frames that take no room, has "ICS
                // 67.080.20" at 34.5 in Word's print, 36.65pt over the
                // margin; ours stood it at the margin — and 177pt down.)
                raiseAtHead(c)
                liftToFoot(c)
                // (A table placed above the anchor's line, after one placed below it
                // that hangs from the same anchor, the paragraph after both: it
                // stands that far above the anchor's place, not above the first one's
                // foot, and the paragraph still goes back to the anchor's place.
                // LibreOffice's tdf97090, tblpY 941 and -36 twips at the right
                // margin: the heading at 372 with the second table at its head
                // and the first 47pt under it; ours stood the second under the
                // first's 700, and the heading under that.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, c.row == 0, c.firstInRow, i > 0, let prevT = _cells[i - 1]?.table, prevT != c.table,
                   let fb = floatRunBase, fb.table == prevT, fb.page == page,
                   let was = document.tableStyles[prevT], was.floatOffsetY != nil, !was.pageAnchored,
                   let ts = document.tableStyles[c.table], !ts.pageAnchored, ts.floatOffsetY == nil, let up = ts.floatRaiseY, ts.floatsOverText {
                    RuleTrace.hit("word-float-above-the-anchor-after-one-below-it-hangs-from-the-same-line")
                    y = max(0, fb.y - _px(up))
                    floatRunBase = (c.table, page, y)
                    if let tf = textFloatTop, tf.table == prevT { textFloatTop = (c.table, page, tf.y, tf.down, false) }
                }
                // (And one placed above the text's place in the middle of a
                // page, up over the paragraphs before it: they stand under it,
                // as the text before a table placed against the page does,
                // below. LibreOffice's floattable-in-section, tblpY -921 under
                // the paragraph after it, has its table 46pt over where that
                // paragraph would stand and the paragraph before it, which
                // would reach into it, under it, 483.7 on the page; ours set
                // it above the table.)
                // (Not across a section break that starts a page: zh-cfb32050's
                // "附件一", tblpY -6 twips, opens the section after a paragraph
                // that ends one, and that paragraph stays on its own page.)
                if theme.wordRules, c.row == 0, c.firstInRow, i > 0, _cells[i - 1]?.table != c.table, y > 0.01, deferredUnder.isEmpty,
                   !(document.paragraphs[i - 1].style.sectionXML != nil && document.paragraphs[i - 1].style.sectionBreaksPage != false),
                   let ts = document.tableStyles[c.table], !ts.pageAnchored, ts.floatOffsetY == nil, let up = ts.floatRaiseY {
                    // (A line a point above the table's top is under it too:
                    // floattable-anchor-next-page's third table, tblpY -269 twips,
                    // has the line before it 0.55pt short of its top, and that
                    // line stands under it, 481.4, in Word's print.)
                    let target = y - _px(up)
                    if target >= 0 {
                        var moved: [PagePiece] = []
                        var edge = y
                        while let last = _pages[page].last, last.paragraph < i, _cells[last.paragraph] == nil, !last.repeated,
                              last.pageY >= target - _px(1) || edge - _px(document.paragraphs[last.paragraph].style.spaceAfter) - Self._multipleSlack(document.paragraphs[last.paragraph].style, last.paragraph < _heights.count ? _heights[last.paragraph] : 0) > target + 0.01 {
                            edge = last.pageY
                            moved.insert(_pages[page].removeLast(), at: 0)
                            if let k = _allPieces.lastIndex(of: moved[0]) { _allPieces.remove(at: k) }
                        }
                        if !moved.isEmpty {
                            deferredUnder = moved
                            deferredTable = c.table
                            reordered = true
                            y = target
                        } else if RichTextTheme.wordWindowsPages, y - target < _px(8) {
                            // (Nothing reaches into it: the 1.5-spaced line above
                            // clears the raise with its glyphs, and the table still
                            // stands its raise up. lo-235e3561: rows at 591, ours 595.)
                            y = target
                        }
                    }
                }
                // A floating table placed against the page stands at its
                // offset there, and the text before it on that page that
                // would reach into it is set under it: lab `fc` (Word 16, a
                // full-width roster table 90pt down a page, its title and a
                // line above it in the file) has the table at the margin and
                // both lines under it; zh-a4b0f6ea p20 has it 183.4pt down,
                // its title above and "单位（盖章）：", whose 28pt line reached
                // into it, under it. Ours set it in the flow, after both.
                // (Not before a break the row opens with: the table stands on
                // the page that break opens. zh-2b21a9d4's form, 48.8pt down
                // its page after a page-break paragraph, took page 2's last
                // four lines under it onto page 3 and left page 2 blank.)
                // (A table floating by the text stands its offset down already:
                // that is not content above it on the page, or the break would
                // open a second page for it — LibreOffice's floattable-header,
                // a page-break paragraph and then a table of tblpY 1 twip, has
                // its table on page 2 in Word's print, ours on page 3.)
                let floatDrop = theme.wordRules && c.row == 0 && (i == 0 || _cells[i - 1]?.table != c.table)
                    ? _px(document.tableStyles[c.table]?.floatOffsetY ?? 0) : 0
                let rowBreaksPage = !sectionBreakHandled && c.firstInRow && _pageBreak[i] && !document.paragraphs[i].style.pageBreakInline
                    && !(document.paragraphs[i].style.breakEndsPrevious && i > 0 && document.paragraphs[i - 1].cell != nil)
                    && (y - floatDrop > 0.01 || !_pages[page].isEmpty || (theme.wordRules && markOnPage))
                if theme.wordRules, c.row == 0, c.firstInRow, i == 0 || _cells[i - 1]?.table != c.table, !rowBreaksPage,
                   case let ts0 = document.tableStyles[c.table], ts0?.pageOffsetY != nil || ts0?.marginOffsetY != nil || ts0?.bottomAligned == true {
                    let physical = page / _columns
                    let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
                    let target = ts0?.pageOffsetY.map { _px($0) - insetTop } ?? bottomAlignedOffset(c, i).map { _px($0) - insetTop } ?? _px(ts0?.marginOffsetY ?? 0)
                    if target > y + 0.01, target < contentH - 0.01 {
                        tableReturn = (c.table, y, page, target)
                        y = target
                        // (A table placed against the page whose first row, or
                        // the whole of it, would pass the page's bottom EDGE is
                        // set up so that it ends there — not at the margin, not
                        // at the footer's place. Lab lh2 (windows, 2026-10-31,
                        // LibreOffice's tdf99140): tblpY 640.85pt, rows of
                        // 283.5pt on a 792pt page: row 1 at 508.03 to 791.64 on
                        // page 1, rows 2 and 3 on page 2 at the margin; rows of
                        // 100pt: all three on page 1 ending at 791.64. A row
                        // that fits below its place is not moved.)
                        if RichTextTheme.wordWindowsPages {
                            let pageBottom = _px(pageSetup(forPage: physical).height) - insetTop
                            var whole = c.rowTop + c.ownRowHeight, k = i
                            while k < count, let d = _cells[k], d.table == c.table { whole = max(whole, d.rowTop + d.ownRowHeight); k += 1 }
                            let total = whole - c.rowTop
                            let height = total <= pageBottom + 0.01 ? total : c.ownRowHeight
                            if y + c.ownRowHeight > pageBottom + 0.01, height <= pageBottom + 0.01 {
                                RuleTrace.hit("page-anchored-table-set-up-to-the-page-edge")
                                y = pageBottom - height - max(c.ruleBelow, ruleUnder(c))
                                pageEdgeClamp = (c.table, pageBottom)
                                keptPastFoot = c.table
                            }
                        }
                    } else if target < -0.01, y < 0.01, _pages[page].isEmpty, target > -insetTop {
                        // (Over the top margin too, where the page opens
                        // with it: zh-19dde9e7's report, a table placed
                        // 58.25pt down a page whose margin is 72, has its
                        // title row's text at 67 in Word's print; ours
                        // stood at the margin, 15pt low.)
                        y = target
                    } else if theme.wordRules, target < -0.01, target > -insetTop, y > 0.01, deferredUnder.isEmpty, {
                        // (A table wholly in the top margin, above where the text
                        // begins, takes no room from it, wherever in the file it
                        // stands: tdf92157's 22.5pt letter-head tag, placed 0.05pt
                        // down the page, follows a paragraph and has the address
                        // table under it 20pt higher in Word's print than ours.)
                        var bottom = c.rowTop + c.ownRowHeight, k = i
                        while k < count, let d = _cells[k], d.table == c.table { bottom = max(bottom, d.rowTop + d.ownRowHeight); k += 1 }
                        return target + (bottom - c.rowTop) <= 0.01
                    }() {
                        tableReturn = (c.table, y, page, target)
                        y = target
                    } else if theme.wordRules, target >= 0, target < y - 0.01, deferredUnder.isEmpty, {
                        // (Not where the text it would take under it does not
                        // fit under its first row: the table stands at its
                        // offset on the next page and the text keeps its
                        // place. zh-8d1a3d99's application form, 64.55pt down
                        // a page, follows a page of rules; Word's print has
                        // the rules on page 1 and the form on page 2, where
                        // ours set the form on page 1 and took every rule
                        // under it. A title or a line that fits under the
                        // first row is taken there, and the table parts —
                        // zh-6cd1befe p51, zh-60173bb6, as `anchoredParts`.)
                        let under = _pages[page].filter { $0.paragraph < i && _cells[$0.paragraph] == nil && !$0.repeated
                            && $0.pageY + ($0.flowBottom - $0.flowTop) > target + 0.01 }
                            .reduce(0.0) { $0 + $1.flowBottom - $1.flowTop }
                        // (And the line under that row, which the row after
                        // carries in its margin and the text set under the
                        // row clears: zh-77bd4900's checklist, 68.7pt down,
                        // ruled 2.25pt between rows, follows a page whose
                        // text fits under its first row by 1.15pt without
                        // that line and not with it — Word's print has the
                        // page whole and the list on the next, where ours
                        // took the page's text under the list's head.)
                        let ts = document.tableStyles[c.table]
                        let line = ts?.edges?.insideH ?? ts?.borders ?? false
                            ? _px(Self._ruleRoom(ts?.edgeStyles["insideH"] ?? ts?.borderStyle, ts?.edgeWidths["insideH"] ?? ts?.borderWidth ?? 0.5)) : 0
                        // (Nor where another table's rows reach past its place:
                        // they cannot be set under it, and the table goes to the
                        // next page at its offset. zh-e49d7943's "演習評鑑編組區分表",
                        // 102pt down its page after a table whose "附記" rows end
                        // 201pt down page 21, heads page 22 in Word's print; ours
                        // set it on page 21 under those rows, 105pt low.)
                        // (Unless they stand clear of it across the page: tdf92157's
                        // address block, placed against the page at the right
                        // margin, is beside the 375pt letter-head table above,
                        // and Word's print has it on page 1 at its offset.)
                        let myLeft = _tableLeft(c.table, document)
                        let myRight = myLeft + (_columnWidths[c.table] ?? []).reduce(0, +)
                        let rowsInTheWay = _pages[page].contains {
                            guard $0.paragraph < i, let other = _cells[$0.paragraph], !$0.repeated, other.table != c.table,
                                  // (Not a table that floats itself: two floating tables lay over each other in Word's print,
                                  // lab ovl13, where a raised table's rows reach 150pt down and the page-anchored one at 84pt
                                  // stays on the page.)
                                  !(theme.wordRules && document.tableStyles[other.table]?.floatsOverText == true),
                                  $0.pageY + ($0.flowBottom - $0.flowTop) > target + 0.01 else { return false }
                            let l = _tableLeft(other.table, document)
                            return l < myRight - 0.01 && myLeft < l + (_columnWidths[other.table] ?? []).reduce(0, +) - 0.01
                        }
                        return rowsInTheWay || target + c.ownRowHeight + line + under > contentH + 0.01
                    }() {
                        newPage()
                        let physical = page / _columns
                        let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
                        let target = ts0?.pageOffsetY.map { _px($0) - insetTop } ?? _px(ts0?.marginOffsetY ?? 0)
                        if target > y + 0.01, target < contentH - 0.01 {
                            tableReturn = (c.table, y, page, target)
                            y = target
                        }
                    } else if target >= 0, target < y - 0.01, deferredUnder.isEmpty {
                        var moved: [PagePiece] = []
                        while let last = _pages[page].last, last.paragraph < i, _cells[last.paragraph] == nil, !last.repeated,
                              last.pageY + (last.flowBottom - last.flowTop) > target + 0.01 {
                            moved.insert(_pages[page].removeLast(), at: 0)
                            if let k = _allPieces.lastIndex(of: moved[0]) { _allPieces.remove(at: k) }
                            if last.pageY <= target + 0.01 { break }
                        }
                        if !moved.isEmpty {
                            deferredUnder = moved
                            deferredTable = c.table
                            reordered = true
                            y = target
                        } else if let last = _pages[page].last, last.paragraph < i, _cells[last.paragraph] != nil, !last.repeated,
                                  _cells[last.paragraph]?.table != c.table {
                            // (Beside the rows above, not over them — see above: it
                            // stands at its offset and the flow goes on from where
                            // it stood.)
                            tableReturn = (c.table, y, page, target)
                            y = target
                        }
                    }
                }
                // A table row is one unbreakable block; every member gets the
                // row's piece so its text paints on the row's page.
                var j = i
                while j < count, let d = _cells[j], d.table == c.table, d.row == c.row { j += 1 }
                let rowBottom = c.rowTop + c.ownRowHeight
                resumeCursor = nil   // a row restarts whole
                // A row whose first paragraph breaks the page before it
                // opens a page as a paragraph's break would: the section
                // break on the paragraph before the table (its next
                // section opening on a new page), or the file's own
                // w:pageBreakBefore in the cell. A break character inside
                // a cell Word ignores. (Lab `sectbl` from bug65649's
                // package: the test record's table on its own page.)
                if !sectionBreakHandled, c.firstInRow, _pageBreak[i], !document.paragraphs[i].style.pageBreakInline,
                   !(document.paragraphs[i].style.breakEndsPrevious && i > 0 && document.paragraphs[i - 1].cell != nil),
                   !rowOpensThePage, y - floatDrop > 0.01 || !_pages[page].isEmpty || (theme.wordRules && markOnPage) {
                    // (After a section's empty mark, which takes no room and leaves its page blank, a table
                    // opening the next section starts the page after it — lo-0ceaa045, 1 page for Word's 2.)
                    newPage()
                    // (In columns a page break goes on to the next page, not
                    // the next column, for a table's first row as for a
                    // paragraph's: tdf153136's second copy, a table after a
                    // page-break paragraph in a two-column section, opens
                    // Word's page 2; ours set it in page 1's second column.)
                    // (A column break is the next column: lo-e311acbade7c85b8's
                    // second table follows a paragraph that breaks the column.)
                    if theme.wordRules, _columns > 1, !document.paragraphs[i].style.columnBreak,
                       !(i > 0 && document.paragraphs[i - 1].style.columnBreak) {
                        while page % _columns != 0 { newPage() }
                    }
                    // (A table placed against the page, at its offset on the
                    // page the break opened.)
                    if theme.wordRules, c.row == 0, i == 0 || _cells[i - 1]?.table != c.table,
                       case let ts0 = document.tableStyles[c.table], ts0?.pageOffsetY != nil || ts0?.marginOffsetY != nil {
                        let physical = page / _columns
                        let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
                        let target = ts0?.pageOffsetY.map { _px($0) - insetTop } ?? _px(ts0?.marginOffsetY ?? 0)
                        if target > y + 0.01, target < contentH - 0.01 {
                            tableReturn = (c.table, y, page, target)
                            y = target
                        }
                    }
                    // (And one placed above the text's place stands up in the
                    // margin on the page the break opened: LibreOffice's
                    // floating-table-section-break, a table 9.85pt up under
                    // the section break, has its text at 58 in Word's print.)
                    raiseAtHead(c)
                liftToFoot(c)
                }
                // (At a page's top the table goes on: its header row
                // again, and the cells merged down from above.)
                func goOn() {
                    guard c.row > 0 else { return }
                    if headerRows(c.table) > 0 { repeatHeader(of: c.table, before: i) }
                    continueSpans(into: i, c)
                }
                // A table placed against the page that does not fit whole
                // where it stands keeps its first row there and goes on
                // at the next page's head: Word sets zh-6cd1befe's 26-row
                // duty table's header row alone on page 51 and the rest
                // on 52, where ours filled 51 from the header down.
                // (The text set under it counts too: the flow takes the
                // table up again under that text, and goes on to the next
                // page with the rows that do not fit there — the text
                // staying where the whole table would end. Lab `t44/A`,
                // Word 16: the roster's header row at its tblpY, "单位（盖
                // 章）" under where the whole table would end, 442 of a 505
                // foot, and the 66pt row 1 on with the rest on page 2;
                // with that line after the table instead, lab C, the
                // table stays whole.) Asked at the first row too, whose
                // centred cells merged down are then set in it alone.
                func anchoredParts() -> (whole: Bool, under: Double)? {
                    guard theme.wordRules, c.row <= 1, c.firstInRow, y > 0.01, document.tableStyles[c.table]?.pageAnchored == true else { return nil }
                    var bottom = rowBottom, next = c.row == 1 ? c.ownRowHeight : 0, second = rowBottom
                    var k = j
                    while k < count, let d = _cells[k], d.table == c.table {
                        bottom = max(bottom, d.rowTop + d.ownRowHeight)
                        if d.row <= 1 { second = max(second, d.rowTop + d.ownRowHeight) }
                        if d.row == 1, next == 0 { next = d.ownRowHeight }
                        k += 1
                    }
                    let under = deferredTable == c.table ? deferredUnder.reduce(0) { $0 + $1.flowBottom - $1.flowTop } : 0
                    // (At the second row, y is the first row's foot.)
                    let rest = bottom - c.rowTop
                    // (Whole while it ends above the footer's place, its
                    // margin or no: zh-0b87285b's 13-row list at its tblpY
                    // ends 530.2pt down a 595pt page — margin at 523, footer
                    // at 545.4 — all on page 6 in Word's print, where ours
                    // kept its header row alone there. zh-6cd1befe's 26 rows
                    // would end at 832.8, under its footer's 792.4 and on
                    // the page, and Word parts them.)
                    let setup = pageSetup(forPage: page / _columns)
                    let edge = max(contentH, _px(setup.height - setup.footerDistance) - _bodyInsets(page: page / _columns, document).top)
                    // (Only where its second row does not fit whole: lab
                    // `pa19` (Word 16, zh-19dde9e7's seven-row table placed
                    // 150pt down) keeps rows 0 to 5 on the page and takes the
                    // tall row 6 alone to the next, though the whole would
                    // end past the foot; ours set the first row alone.)
                    // (Not a row taller than any page, which no page holds whole: it parts
                    // here, from under the first row — LibreOffice's tdf172156, a 896pt
                    // row of empty lines in a floating table 182pt down the page, starts
                    // on page 1 in Word's print and goes on over page 2.)
                    if y + (second - c.rowTop) > edge + 0.01 {
                        if RichTextTheme.wordWindowsPages, c.row == 1, second - c.rowTop > contentH + 0.01 { RuleTrace.hit("row-taller-than-a-page-parts-where-it-stands"); return nil }
                        return (true, 0)
                    }
                    if under > 0, y + rest + under + next > contentH + 0.01 { return (false, rest) }
                    return nil
                }
                let partsAfterFirst = c.row == 0 && anchoredParts() != nil && j < count && _cells[j]?.table == c.table
                if c.row == 1, let parts = anchoredParts() {
                    if parts.whole {
                        newPage()
                    } else {
                        // (The cells merged down from the first row go on
                        // from its foot, not from under that text.)
                        let foot = y
                        // (No lower than lets it stand on this page: zh-60173bb6's
                        // "附件1" title, three 28.8pt lines before a table placed
                        // 248.5pt down whose whole would end past the foot, is at
                        // that page's foot in Word's print, 626-685, the table's
                        // first row above it and the rest on the next page; ours
                        // set it under the whole and took it to a page of its own.)
                        let held = deferredUnder.reduce(0.0) { $0 + $1.flowBottom - $1.flowTop }
                        y += theme.wordRules && contentH - foot - held >= 0 ? min(parts.under, contentH - foot - held) : parts.under
                        placeDeferred()
                        y = foot
                        newPage()
                    }
                }
                // A table floating by the text, straight after another table
                // and placed up over it (a tblpY of none or less), that does
                // not fit whole where it stands and would on a page of its
                // own goes to the next page whole: zh-694447ca's 34-row
                // equipment list, tblpY -85 under the table before it, has
                // its header row at page 15's head in Word's print and page
                // 14 ends with the two rows before it; ours filled 14 to
                // the foot and took two rows to 15. (Not one after a
                // paragraph, or placed down from the table before: those
                // part — zh-efd9229a's at tblpY 412 after a paragraph and
                // zh-cd48112c's at 169 after a table go on over the page
                // in Word's prints. Nor one longer than a page, as
                // zh-38758b14's three-page scoring table.)
                if theme.wordRules, c.row == 0, c.firstInRow, y > 0.01, i > 0, let before = _cells[i - 1]?.table, before != c.table,
                   let ts = document.tableStyles[c.table], ts.floatsOverText, !ts.pageAnchored,
                   let kept = ts.keptPosition, let at = kept.rangeOfSubstring("w:tblpY=\""),
                   let raised = Double(kept[at.upperBound...].prefix { $0 == "-" || $0.isNumber }), raised <= 0 {
                    var bottom = rowBottom, k = j
                    while k < count, let d = _cells[k], d.table == c.table { bottom = max(bottom, d.rowTop + d.ownRowHeight); k += 1 }
                    let whole = bottom - c.rowTop
                    // (Whole while it ends above the footer's place, as a
                    // table placed against the page: its 649pt end 7pt
                    // past the margin on page 15, over the footer's 49.6.)
                    let setup = pageSetup(forPage: page / _columns)
                    let edge = max(contentH, _px(setup.height - setup.footerDistance) - _bodyInsets(page: page / _columns, document).top)
                    if y + whole > edge + 0.01, whole <= edge - 0.01 { newPage(); raiseAtHead(c) }
                }
                // (A run of rows kept with the next — each row's first
                // paragraph says `w:keepNext` — goes to the next page with
                // the first row after it that does not keep, where this
                // page cannot hold them and one page can: zh-147bdae0's
                // four kept indicator rows and its "聯絡資訊" row open page
                // 39 in Word's print, its header row alone at page 38's
                // foot; ours filled 38 with two of them. A run longer than
                // a page parts as rows do: zh-64044a1d's equipment list
                // keeps every row with the next, and Word parts it between
                // "8" and "9".)
                // (Of the row after the run, its first line in each cell is
                // all that must follow — all of it where it may not part:
                // zh-499adba6's kept heading row "在政策決策機制方面" over a
                // row of long paragraphs stays at page 7's foot with that
                // row's first lines. Nor a run a kept paragraph before the
                // table began: that run is the paragraphs' own — bug65649.)
                let carried = c.row == 0 && i > 0 && _cells[i - 1] == nil && document.paragraphs[i - 1].style.keepNext
                // (A row is kept with the next only where the first paragraph of
                // every one of its cells says so: lo floattable-header's "A2: page
                // 2" is Heading 1, which keeps with the next, beside a cell that
                // does not, and Word's print leaves the row on page 2 under the
                // header row, where ours took it to page 3 and left page 2 empty.)
                var rowKept = document.paragraphs[i].style.keepNext
                if rowKept, theme.wordRules, RichTextTheme.wordWindowsPages, _cells[i] != nil {
                    var m = i
                    while m < count, let e = _cells[m], e.table == c.table, e.row == c.row {
                        if m == i || _cells[m - 1]?.column != e.column, !document.paragraphs[m].style.keepNext { rowKept = false; RuleTrace.hit("row-kept-only-if-every-cell-keeps") }
                        m += 1
                    }
                }
                if theme.wordRules, c.firstInRow, y > 0.01, !carried, rowKept {
                    var previous: Int? = nil
                    var b = i - 1
                    while b >= 0, let d = _cells[b], d.table == c.table, d.row == c.row - 1 { previous = b; b -= 1 }
                    if !(previous.map { document.paragraphs[$0].style.keepNext } ?? false) {
                        var k = i, row = c.row
                        var follower: (top: Double, height: Double)? = nil
                        while k < count, let d = _cells[k], d.table == c.table {
                            if d.row != row {
                                row = d.row
                                if !document.paragraphs[k].style.keepNext {
                                    var need = 0.0
                                    if document.tableStyles[c.table]?.rowsCantSplit.contains(d.row) == true {
                                        need = d.ownRowHeight
                                    } else {
                                        var m = k
                                        while m < count, let e = _cells[m], e.table == c.table, e.row == d.row {
                                            if m == k || _cells[m - 1]?.column != e.column {
                                                let g = geometry(m)
                                                let first = document.paragraphs[m].image != nil ? _heights[m] : (Self._lineBottoms(g.painter).first ?? _heights[m])
                                                need = max(need, (g.textTop - g.top) + first + e.pad.top + e.pad.bottom)
                                            }
                                            m += 1
                                        }
                                        need = need > 0 ? min(need, d.ownRowHeight) : d.ownRowHeight
                                    }
                                    follower = (d.rowTop, need)
                                    break
                                }
                            }
                            k += 1
                        }
                        if let follower {
                            let need = follower.top - c.rowTop + follower.height
                            if y + need > contentH + 0.01, need <= contentH - 0.01 { newPage() }
                        }
                    }
                }
                // (A floating table in a file that says so is not parted over
                // pages: it goes whole to the next one where that holds it,
                // and stays whole where nothing does. LibreOffice's
                // do-not-break-wrapped-tables, two 90pt rows from the head of
                // a 166pt page, has both on the first page in Word's print.)
                let keepsWhole = theme.wordRules && document.doNotBreakWrappedTables
                    && document.tableStyles[c.table]?.keptPosition != nil
                if keepsWhole, c.firstInRow, c.row == 0, y > 0.01 {
                    var bottom = rowBottom, k = j
                    while k < count, let d = _cells[k], d.table == c.table { bottom = max(bottom, d.rowTop + d.ownRowHeight); k += 1 }
                    let whole = bottom - c.rowTop
                    if y + whole > contentH + 0.01, whole <= contentH - 0.01 { newPage() }
                }
                let atTop = y < 0.01
                if atTop { goOn() }
                // A row made taller in the flow for a cell merged down
                // into it need not be so here, where that cell's text
                // was taken up again at the head of the page: it is as
                // tall as what is left of the cell asks, and no shorter
                // than itself. (Word lays the rows of each page out
                // with what the page holds: the room lost at the foot
                // of the page before is not owed again under the cell.)
                func pageHeight() -> Double {
                    // (Not only where the flow stretched it: zh-38d26944's
                    // "成果精度" cell, centred and merged over rows 16 and 17,
                    // fits the two rows in the flow; Word keeps its first
                    // line in row 16 on p12 and grows row 17 on p13 to the
                    // two it takes over, 53.16 where the row is 45.14.)
                    guard theme.wordRules else { return c.ownRowHeight }
                    var need = 0.0, continued = false
                    for piece in _pages[page] where piece.part != .rules && piece.paragraph < i && !piece.repeated {
                        let m = piece.paragraph
                        guard let d = _cells[m], d.table == c.table, d.row < c.row, !d.vertical,
                              (c.row ... c.row + c.ghostRows).contains(d.row + d.rowSpan - 1) else { continue }
                        if piece.part == .text { continued = true }
                        need = max(need, piece.pageY + (min(piece.flowBottom, _tops[m] + _heights[m]) - piece.flowTop) + d.pad.bottom - y)
                    }
                    // (Taller than the flow made it, too: a cell that left
                    // one line with the row above and took four over the
                    // page asks this row for all four.)
                    return continued ? max(c.ownRowHeight - c.stretched, need) : c.ownRowHeight
                }
                // (Under a pinned float that it would run into: see
                // `_pinnedFloats`.)
                if c.firstInRow { underPins(c.ownRowHeight) }
                var shown = pageHeight()
                // (`STARLING_RICHTEXT_ROWS=<page>` prints each row as it
                // is set on that page: where it stands, what is left,
                // and what it asks.)
                if let traced = Self.debugRows, traced == page + 1 {
                    let line = "row \(c.row) of \(c.table) at \(i): y \(y / _px(1))pt of \(contentH / _px(1)), shown \(shown / _px(1)), own \(c.ownRowHeight / _px(1)), rule under \(ruleUnder(c) / _px(1)), top \(atTop)\n"
                    FileHandle.standardError.write(Data(line.utf8))
                }
                wentOver = false
                // (Down to the footer's place: zh-5a9a85c6's first row ends
                // at 792.0, the footer's place 792.4.)
                var pastFoot = keepsWhole && c.row > 0 && y > 0.01
                if keptPastFoot == c.table, c.row == 0 {
                    let setup = pageSetup(forPage: page / _columns)
                    let edge = pageEdgeClamp?.table == c.table ? pageEdgeClamp!.edge : _px(setup.height - setup.footerDistance) - _bodyInsets(page: page / _columns, document).top
                    // (A row taller than the body cannot be kept whole past the foot: it parts, as Word does with
                    // dx2 bede0fbc's 694pt wrapper row, whose remainder went missing when kept.)
                    pastFoot = y + shown + ruleUnder(c) <= edge + 0.01 && shown <= contentH + 0.01
                } else if keptPastFoot == c.table {
                    keptPastFoot = nil
                }
                if theme.wordRules, !pastFoot, shown + ruleUnder(c) > contentH - y + 0.01, splitRow(i, j, c, atTop: atTop) {
                    // (A row that ends at the margin leaves the next of a page-anchored table in compat 12 to part by lines to the
                    // page's own foot, where it is the table's own and begun here: lo-c9b8c5ab's A4 ends 468.1 of 468 and A5
                    // stands four lines on page 1 in Word's print.)
                    let nextParts = RichTextTheme.wordWindowsPages && (document.compatibilityMode ?? 12) < 15 && j < count
                        && document.tableStyles[c.table]?.pageAnchored == true && _cells[j]?.table == c.table
                        && document.tableStyles[c.table]?.rowHeights[_cells[j]!.row].map({ _cells[j]!.ownRowHeight > _px($0) + _px(2) }) ?? true
                        && y < _px(pageSetup(forPage: page / _columns).height) - _bodyInsets(page: page / _columns, document).top - _px(14)
                    if y > contentH - 0.01, !tableEndsOverAnchor(c, j), !nextParts { newPage() }
                    i = j
                    continue
                }
                if wentOver {
                    // (The row went to a new page whole: there it is laid
                    // out again, and parted if the page cannot hold it.)
                    // (A floating table placed up over the text, taken to the
                    // new page whole, stands that much up there too:
                    // floattable-next-leaf-in-section's second table, tblpY
                    // -289 under a table that fills page 1, has its first
                    // line 12pt over the margin on page 2 in Word's print;
                    // ours stood it at the margin.)
                    raiseAtHead(c)
                    // (A floating table's first row taken whole to the next page by its own part stands its offset
                    // down that page too, as one taken there before it is set: lab compat1415b rows19, compat 14,
                    // A1 at 66.0 on page 2 with tblpY 323 twips.)
                    if theme.wordRules, c.row == 0, c.firstInRow, y < 0.01, i == 0 || _cells[i - 1]?.table != c.table,
                       let down = document.tableStyles[c.table]?.floatOffsetY, down > 0, !(document.tableStyles[c.table]?.pageAnchored ?? false),
                       // (Not when the row, clamped to the page, would then no longer fit: lo-a48482e7's A2 fills page 3 and
                       // stands there in Word's print under its 1-twip offset.)
                       pageHeight() + ruleUnder(c) + _px(down) <= contentH + 0.01 {
                        RuleTrace.hit("floating-table-first-row-carried-whole-stands-its-offset-down")
                        y += _px(down)
                    }
                liftToFoot(c)
                    underPins(c.ownRowHeight)
                    shown = pageHeight()
                    if shown + ruleUnder(c) > contentH - y + 0.01, splitRow(i, j, c, atTop: true) {
                        if y > contentH - 0.01 { newPage() }
                        i = j
                        continue
                    }
                } else if !atTop, !pastFoot, shown + ruleUnder(c) > contentH - y + 0.01, y > 0.01 {
                    newPage()
                    // (A floating table's first row taken to the next page
                    // stands its offset down that page too: zh-0243e7fc's
                    // p11 form, tblpY 272 twips under text, has its first
                    // line 13pt lower in Word's print than ours at the top.)
                    if theme.wordRules, c.row == 0, c.firstInRow, i == 0 || _cells[i - 1]?.table != c.table,
                       let down = document.tableStyles[c.table]?.floatOffsetY, !(document.tableStyles[c.table]?.pageAnchored ?? false) {
                        y += _px(down)
                    }
                    // (And one placed against the page stands at its offset
                    // on the page it went to — up into the top margin too:
                    // zh-0513f641's p9 form, tblpY 1322 against a 1440
                    // margin after the cover that fills p8, has its top line
                    // at 66.0 in Word's print; ours stood it at the margin.)
                    if theme.wordRules, c.row == 0, c.firstInRow, i == 0 || _cells[i - 1]?.table != c.table,
                       case let ts0 = document.tableStyles[c.table], ts0?.pageOffsetY != nil || ts0?.marginOffsetY != nil, _pages[page].isEmpty {
                        let physical = page / _columns
                        let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
                        let target = ts0?.pageOffsetY.map { _px($0) - insetTop } ?? _px(ts0?.marginOffsetY ?? 0)
                        if target > y + 0.01, target < contentH - 0.01 {
                            tableReturn = (c.table, y, page, target)
                            y = target
                        } else if target < -0.01, target > -insetTop {
                            y = target
                        }
                    }
                    // (A table placed up over the text taken to this page
                    // from the foot of the last stands up there too: the
                    // floattable-tab-join pair and floattable-object-formatter,
                    // tblpY -179 twips on a landscape page, have the second
                    // table start 9pt up in the margin on page 2 in Word's
                    // print and keep all three rows there; ours stood it at
                    // the margin and sent the third row to page 3.)
                    raiseAtHead(c)
                liftToFoot(c)
                    goOn()
                    underPins(c.ownRowHeight)
                    shown = pageHeight()
                } else if theme.wordRules, !atTop, y > 0.01, j < count, _cells[j] == nil, document.paragraphs[i].style.keepNext,
                          !_pageBreak[j], !document.paragraphs[j].style.pageBreakBefore {
                    // (A row whose first paragraph keeps with the next is
                    // kept with the paragraph after its table, as a
                    // paragraph is: that one's first line, two under widow
                    // control, all of a short one. Lab `kn` (Word 16, modes
                    // 14, 15 and legacy): a four-paragraph row that fits a
                    // page's foot with no room for the line after the
                    // table goes over with it. form_footnotes'
                    // "INSTRUCTIONS" box, opened by a Heading 5, fits page
                    // 2's foot by 5pt but not with the document's last mark
                    // under it, and Word takes both to page 3. Not where
                    // that paragraph opens a page of its own: zh-9e08ed28's
                    // row "3、推廣…" stays at page 15's foot, the heading
                    // after it led by a page break. Nor, unmeasured, with
                    // the table's next row: zh-64044a1d's equipment list
                    // keeps every row with the next and Word parts it
                    // between "8" and "9".)
                    let st = document.paragraphs[j].style
                    let g = geometry(j)
                    let lines = g.painter.computeLineMetrics().count
                    let bottoms = Self._lineBottoms(g.painter)
                    let need = st.keepLines || lines <= 1 || (st.widowControl && !document.widowControlSuspended && lines <= 3) || bottoms.isEmpty ? _heights[j]
                        : (g.textTop - g.top) + bottoms[min(bottoms.count - 1, st.widowControl && !document.widowControlSuspended ? 1 : 0)]
                    if shown + ruleUnder(c) + need > contentH - y + 0.01 {
                        newPage()
                        goOn()
                        shown = pageHeight()
                    }
                }
                // (A row that opens a page the table goes on over, with no
                // header row over it, stands under the table's top line where
                // a cell of it states no top line of its own — as a part
                // going on does, see `splitRow`: zh-cec9d337's p19 opens with
                // row 四, its middle cell of no top line, and Word draws the
                // table's 3pt compound line over that cell and sets the row's
                // text under it, 3.9pt lower than ours.)
                if theme.wordRules, y < 0.01, c.firstInRow, case let extra = headLift(i, j, c), extra > 0.01,
                   shown + extra + ruleUnder(c) <= contentH + 0.01 {
                    y += extra
                }
                if abs(shown - c.ownRowHeight) > 0.01 {
                    // Its cells' text from where each stands in a row of
                    // that height, and its rules: their last stretch with
                    // the line under it, under as much of their middle
                    // as a taller row needs.
                    let spare = c.ownRowHeight - shown
                    let edge = min(_px(2), c.ownRowHeight / 4)
                    for k in i ..< j {
                        let d = _cells[k]!
                        let down = d.rowSpan > 1 ? 0 : d.verticalAlign == "center" ? spare / 2 : d.verticalAlign == "bottom" ? spare : 0
                        var text = PagePiece(paragraph: k, flowTop: c.rowTop + down,
                                             flowBottom: d.rowSpan > 1 ? c.rowTop + d.rowHeight : c.rowTop + down + shown, page: page, pageY: y)
                        text.part = .text
                        add(text)
                        guard k == i else { continue }
                        var at = y, left = shown
                        while left > c.ownRowHeight + 0.01 {
                            let top = at == y ? c.rowTop : c.rowTop + edge
                            let take = min(rowBottom - edge - top, left - edge)
                            var middle = PagePiece(paragraph: i, flowTop: top, flowBottom: top + take, page: page, pageY: at)
                            middle.part = .rules
                            middle.inner = true
                            add(middle)
                            at += take
                            left -= take
                        }
                        var rules = PagePiece(paragraph: i, flowTop: rowBottom - left, flowBottom: rowBottom, page: page, pageY: at)
                        rules.part = .rules
                        rules.inner = true
                        add(rules)
                    }
                    y += shown
                    if y > contentH - 0.01 { newPage() }
                    i = j
                    continue
                }
                // A cell merged down, centred or set at the bottom, whose
                // rows do not all fit on this page is set in the rows that
                // do: zh-6d1afa56's "工程建设项目招标投标信息" spans rows 5
                // and 6, row 6 goes to the next page, and Word centres the
                // four lines in row 5 — where centring them over both put
                // them 40pt low, half of them over the page's foot.
                var lift: [Int: Double] = [:]
                if theme.wordRules, (i ..< j).contains(where: { _cells[$0]!.rowSpan > 1 }) {
                    // The rows below, as tall as each stands, while they fit.
                    var heights: [Int: Double] = [c.row: c.ownRowHeight]
                    var n = j
                    while n < count, let d = _cells[n], d.table == c.table {
                        if heights[d.row] == nil { heights[d.row] = d.ownRowHeight }
                        n += 1
                    }
                    var column: [Int: (first: Int, last: Int)] = [:]
                    for k in i ..< j { let d = _cells[k]!; column[d.column] = (column[d.column]?.first ?? k, k) }
                    // What of row `r`, after `part` of a merge on this
                    // page, stays on the page where the row parts at its
                    // foot (0 where it goes over whole).
                    func partingKept(_ r: Int, after part: Double) -> Double {
                        guard let first = (j ..< count).first(where: { _cells[$0]?.table == c.table && _cells[$0]?.row == r }),
                           let e = _cells[first], document.tableStyles[c.table]?.rowsCantSplit.contains(r) != true,
                           !document.paragraphs[first].style.keepNext,
                           _px(document.tableStyles[c.table]?.rowHeights[r] ?? 0) <= contentH - y - part - ruleUnder(e, parted: true) + 0.01 else { return 0 }
                            // (The line that closes the page, as `splitRow` cuts the row by it:
                            // zh-e1b09977's "農委會", merged over a row that parts under the table's
                            // 2.16 bottom line, stands in the nine lines that stay, 9pt higher than
                            // the ten the smaller line counted.)
                            let closing = theme.wordRules && RichTextTheme.wordWindowsPages ? ruleClosing(e) : ruleUnder(e, parted: true)
                            let limit = e.rowTop + (contentH - y - part) - closing + 0.01
                            // (A row whose cells are merged down over rows that
                            // hold nothing parts only at one of those rows' tops
                            // (lab `mg`, `ghostBounds`): it keeps the last that
                            // fits. zh-9ef811c8's "综合业务", merged from the row
                            // above into "监督检查" — itself merged over empty
                            // rows, parting at page 4's foot — stands centred
                            // down to that part's foot in Word's print (333.1);
                            // ours, finding no cell of one row to weigh, centred
                            // it in the row above alone, 43pt high.)
                            if theme.wordRules, !e.ghostBounds.isEmpty {
                                return e.ghostBounds.last(where: { $0 + ruleUnder(e) <= contentH - y - part + 0.01 }) ?? 0
                            }
                            // (Only where the row does part there: every cell
                            // of it keeps a line on the page, else it goes
                            // over whole — see `splitRow`.)
                            var kept = 0.0
                            var columns: [Int: Bool] = [:]   // column → keeps something here
                            var n = first
                            while n < count, let f = _cells[n], f.table == c.table, f.row == r {
                                if f.rowSpan == 1, !f.vertical {
                                    let cut = cellCuts(n).last(where: { $0 <= limit && $0 > e.rowTop + 0.01 })
                                    // (A centred cell whose text fits the part is
                                    // set in it, as tall as its text — see
                                    // `splitRow` — not where the whole row's
                                    // middle put it: zh-84702a67's "10" and two
                                    // blank cells beside a top-set cell of two
                                    // lines made the part 9.5pt deeper, and its
                                    // "是否存在转包、挂靠行为" 5pt low.)
                                    // (The column's whole block, from its first
                                    // paragraph: zh-17ac8aa2's "获取信息的方式" cell,
                                    // three lines of which two fit, read from its
                                    // second as two that fit — its part 52.5, not
                                    // the 65.7 to the cut, and "所需信息情况" beside
                                    // it centred 6.7pt high.)
                                    var block = 0.0
                                    var m = n
                                    while m > first, let h = _cells[m - 1], h.table == c.table, h.row == r, h.column == f.column { m -= 1 }
                                    let blockFirst = m
                                    while m < count, let h = _cells[m], h.table == c.table, h.row == r, h.column == f.column { block += _heights[m]; m += 1 }
                                    let centred = f.verticalAlign == "center" || f.verticalAlign == "bottom"
                                    let whole = centred && block + f.pad.top + f.pad.bottom <= limit - e.rowTop
                                    if whole {
                                        kept = max(kept, block + f.pad.top + f.pad.bottom)
                                    } else if let cut {
                                        // (A centred cell parted at the foot is measured from its text's top, as `splitRow`
                                        // does: zh-9bcea239's "6" row keeps 41pt, its three centred lines cut after two
                                        // — the 50pt from the row's top centred "企业管理（300分）" 4pt low.)
                                        let from = RichTextTheme.wordWindowsPages && f.verticalAlign == "center" ? max(e.rowTop, _tops[blockFirst] - f.pad.top) : e.rowTop
                                        kept = max(kept, cut - from + f.pad.bottom)
                                    }
                                    // (One set whole in the part keeps it, though the
                                    // whole row's middle puts its last line past the
                                    // foot: zh-1eeb9f9a's "其他政策文件", two lines
                                    // centred in a 102pt row that parts with 68 on
                                    // page 8 — ours, finding no cut of it there,
                                    // centred "公开渠道和载体", merged down into that
                                    // row, over the rows above alone, 8pt low.)
                                    columns[f.column] = (columns[f.column] ?? false) || cut != nil || whole || document.paragraphs[n].text.isEmpty
                                }
                                n += 1
                            }
                            // (And no shorter than the row says it is, as
                            // `splitRow` sets the part: Word's
                            // "5.要求行政机关确认…" keeps 40.1pt on zh-91e44bcb's
                            // page 4, its stated 38.95 and its rule, where its
                            // line and margin are 33.2.)
                            let ts = document.tableStyles[c.table]
                            let stated = ts.flatMap { ts in ts.rowsExactHeight.contains(r) ? nil : ts.rowHeights[r] }
                                .map { _px($0) + max(0, e.rules - e.ruleBelow) } ?? 0
                            return kept > 0 && columns.values.allSatisfy({ $0 }) ? min(max(kept, stated), contentH - y - part) : 0
                    }
                    // (Turned, its text is set along the rows that fit: Word
                    // centres zh-b4d36718's "基本公共服务事项", merged over 35
                    // rows of which 26 are on page 14, in those 26; ours
                    // centred it over all 35, 80pt low, and "公共文化类" ran
                    // off the page's foot.)
                    for (_, g) in column {
                        let d = _cells[g.first]!
                        guard d.rowSpan > 1, d.vertical else { continue }
                        var part = 0.0, r = c.row
                        while r < c.row + d.rowSpan, case let h = heights[r] ?? 0,
                              part + h + ruleUnder(c, across: true) <= contentH - y + 0.01 { part += h; r += 1 }
                        // (… and down to the foot through a row that parts
                        // there, as an upright merge is: zh-65e6c317's
                        // "项目（课题）分解" spans a 50pt row and one its other
                        // cell makes 432pt, which parts at page 6's foot; Word
                        // centres it in the 286pt down to the foot, ours in
                        // the first row's 50, its "项目" over the cell's top.)
                        if theme.wordRules, part > 0, r < c.row + d.rowSpan { part += partingKept(r, after: part) }
                        let turned = part > 0 && part < d.rowHeight - 0.01 ? part : nil
                        for k in g.first ... g.last { _cells[k]?.turnedPart = turned }
                        // (… and wrapped to the rows that fit, not to the whole
                        // merge: Word's print of zh-b4d36718's "基本公共服务事项",
                        // merged over rows that part at page 16's foot, is "基本公共
                        // 服务" and "事项" in two columns of the 59pt left there;
                        // ours stood it in one eight characters long, off the foot.)
                        if theme.wordRules, RichTextTheme.wordWindowsPages { _wrapTurned(g.first, g.last, d, turned, document) }
                    }
                    for (_, g) in column {
                        let d = _cells[g.first]!
                        guard d.rowSpan > 1, !d.vertical, d.verticalAlign == "center" || d.verticalAlign == "bottom" else { continue }
                        var part = 0.0, r = c.row
                        // (A row fits with its rule under it, as the rows
                        // are set below: zh-90e0cea8's "行政审批各阶段帮办服务
                        // 内容" was centred over a thirteenth row that fits
                        // page 8 only without its line, and goes over — half
                        // a row, 8.6pt, under Word's.)
                        // (A row with no cell of its own — every one merged
                        // down into it — takes no room: zh-84702a67's row 6.)
                        while r < c.row + d.rowSpan, !(partsAfterFirst && r > c.row), case let h = heights[r] ?? 0,
                              part + h + ruleUnder(c, across: true) <= contentH - y + 0.01 { part += h; r += 1 }
                        // (… and the part of the next that parts at the
                        // page's foot, to the last of its lines kept there:
                        // zh-91e44bcb's "（五）不予处理" and "三、本年度办理结果"
                        // stand midway down to the first line of "5.要求行
                        // 政机关确认…", which goes on over the page, in Word's
                        // print — ours stopped at the row above it, 20pt high;
                        // zh-84702a67's "是否存在转包、挂靠行为" 80pt.)
                        // (Not one whose stated height has no room there,
                        // which goes over whole — see `splitRow`: zh-6cd1befe's
                        // "事故灾难类" ends with "重污染天气事件", at least
                        // 43.65pt with 33 left on page 48, and Word centres it
                        // in the rows above that one.)
                        if !partsAfterFirst, r < c.row + d.rowSpan { part += partingKept(r, after: part) }
                        if Self.debugRows == page + 1 {
                            FileHandle.standardError.write(Data("centred-span cell \(g.first): part \(part / _px(1)) rowHeight \(d.rowHeight / _px(1)) rows \(c.row)..\(r) of \(d.rowSpan) partsAfterFirst \(partsAfterFirst) avail \((contentH - y) / _px(1))\n".utf8))
                        }
                        guard part > 0, part < d.rowHeight - 0.01 else { continue }
                        // (What it was given to spare over the whole span:
                        // above its text and below it, less its margins.)
                        let free = (_tops[g.first] - c.rowTop) + (c.rowTop + d.rowHeight - _tops[g.last] - _heights[g.last])
                            - d.pad.top - d.pad.bottom
                        var up = min(max(0, free), d.rowHeight - part) * (d.verticalAlign == "center" ? 0.5 : 1)
                        // (A centred cell whose text does not fit the part:
                        // the lines that do stand centred in it, the rest
                        // going on at the next page's head. zh-6d1afa56 p25:
                        // "《预算法》…", nine 18pt lines merged over a 98.8pt
                        // row and an 80.8 one, five on page 25 4.4 down —
                        // 17.2 under the rule in Word's print, ours 13.2 —
                        // and the four others at page 26's top.)
                        let text = _tops[g.last] + _heights[g.last] - _tops[g.first]
                        let room = part - d.pad.top - d.pad.bottom
                        if d.verticalAlign == "center", free > 0, text > room + 0.01 {
                            // (Its lines down to the cut, which leaves no
                            // bottom margin on this page — the cell's foot
                            // is on the next: zh-21421b7d's "所需信息情况",
                            // ten 26pt lines in a part of 260.5, stands at
                            // the part's top in Word's print, its tenth
                            // under the cut; ours kept nine and centred
                            // them 13pt down.)
                            let room = part - d.pad.top
                            var shown = 0.0
                            for k in g.first ... g.last {
                                for cut in cellCuts(k) where cut - _tops[g.first] <= room + 0.01 { shown = max(shown, cut - _tops[g.first]) }
                            }
                            if shown > 0 {
                                // (Word centres the lines that stay in the part, even when that is lower
                                // than the whole span's centre: zh-38d26944's "成果精度", one 26pt line
                                // of three, in a 45pt row at page 12's foot, 9.5 down in Word's print.)
                                let want = free / 2 - (room - shown) / 2
                                up = theme.wordRules && RichTextTheme.wordWindowsPages ? want : max(0, want)
                            }
                            if Self.debugRows == page + 1 {
                                FileHandle.standardError.write(Data("centred-part cell \(g.first): part \(part / _px(1)) free \(free / _px(1)) text \(text / _px(1)) room \(room / _px(1)) shown \(shown / _px(1)) cuts \((g.first ... g.last).map { k in cellCuts(k).map { ($0 - _tops[g.first]) / _px(1) } })\n".utf8))
                            }
                        }
                        for k in g.first ... g.last { lift[k] = up }
                    }
                }
                for k in i ..< j {
                    // A cell spanning rows paints through every row it covers.
                    let bottom = _cells[k]!.rowSpan > 1 ? c.rowTop + _cells[k]!.rowHeight : rowBottom
                    guard let up = lift[k], abs(up) > 0.01 else {
                        add(PagePiece(paragraph: k, flowTop: c.rowTop, flowBottom: bottom, page: page, pageY: y))
                        continue
                    }
                    // (Its text lifted, its shading and rules where they were.)
                    var text = PagePiece(paragraph: k, flowTop: c.rowTop + up, flowBottom: bottom, page: page, pageY: y)
                    text.part = .text
                    add(text)
                    var rules = PagePiece(paragraph: k, flowTop: c.rowTop, flowBottom: bottom, page: page, pageY: y)
                    rules.part = .rules
                    rules.inner = true
                    add(rules)
                }
                y += c.ownRowHeight
                // (What follows a table floating by the text keeps its bottomFromText clear of it: Word
                // for Windows' print of LibreOffice's lo-7cba9019, 43 twips, puts the second floating table
                // 2.1pt and the normal table under it 2.3pt lower than ours, which ignored the distance.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, j >= count || _cells[j]?.table != c.table,
                   let gap = document.tableStyles[c.table]?.floatBottomGap { y += _px(gap) }
                if y > contentH - 0.01, !tableEndsOverAnchor(c, j) { newPage() }
                i = j
                continue
            }
            defer { i += 1 }
            let top = _tops[i]
            let bottom = top + _heights[i]
            // (One of no height takes its place on the page all the same.)
            if bottom - top < 0.01 { pageFresh = false }
            // A section of one empty paragraph has a page of its own, and
            // the next section starts on the page after it — Word leaves
            // that page blank (zh-06c46ba9's page 2). A page break just
            // before a section's end is that same break, not a second one:
            // the empty paragraph that ends the section stays on the page
            // the break ends. Lab `es` (`body54.py`), in two packages,
            // 2026-10-14, all six cases; it replaces a mode-14 rule for
            // zh-9e08ed28 (which is the second case) and accounts for
            // zh-ae655121 too.
            let st0 = document.paragraphs[i].style
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
            if theme.wordRules, endsSection, resumeCursor == nil, y > 0.01, _columns == 1, i + 1 < count,
               document.paragraphs[i + 1].style.breakEndsPrevious, _pageBreak[i + 1],
               !document.paragraphs[i + 1].style.pageBreakInline,
               contentH - y < _markLineHeight(i, document) - 0.01 {
                newPage()
            }
            // (In a compat 15 file the empties after the first, which stand past the foot, go with it: lab
            // compat1415b, 11pt lines with 10 after and 16pt left, put the first on the page and the
            // second table at the next page's head under none of them; a first that does not fit
            // goes over with the rest, as in compat 14.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, (document.compatibilityMode ?? 12) >= 15, resumeCursor == nil, y >= contentH - 0.01,
               _columns == 1, i > 0, _cells[i - 1] == nil, document.paragraphs[i - 1].text.isEmpty, document.paragraphs[i].text.isEmpty,
               document.paragraphs[i].image == nil, document.paragraphs[i].style.frameXML == nil, !_pageBreak[i] {
                var k = i
                while k < count, _cells[k] == nil, document.paragraphs[k].text.isEmpty { k += 1 }
                if k < count, _cells[k] != nil, Self._followsFloatingTable(k, _cells[k]!.table, document: document, cells: _cells) {
                    RuleTrace.hit("compat15-empties-past-the-foot-before-a-floating-table-are-absorbed")
                    y += _heights[i]
                    continue
                }
            }
            // (An empty paragraph between two tables floating by the text, in a compat 14 file: Word
            // carries it to the next page unless its space after fits there too — lab compat1415b,
            // Calibri 11pt lines 15.4 over 10 after on a page with 16pt left: both empties go to the
            // next page and the second table stands under them, where 0 after leaves the first one.)
            var emptyBegins = y
            if let last = lastEmptyAt, last.i == i - 1, last.page == page { emptyBegins = max(y, last.y + _heights[i - 1]) }
            if theme.wordRules, RichTextTheme.wordWindowsPages, resumeCursor == nil, y > 0.01,
               // (Compat 15 carries a lone empty between the tables, lab compat1415b after2; of two or more the ones past the foot are absorbed.)
               (document.compatibilityMode ?? 12) < 15 || (i > 0 && _cells[i - 1] != nil && i + 1 < count && _cells[i + 1] != nil),
               _columns == 1, document.paragraphs[i].text.isEmpty, document.paragraphs[i].image == nil, document.paragraphs[i].style.frameXML == nil,
               case let pst = document.paragraphs[i].style, case let after = _px(pst.spaceAfter),
               // (Its line counts as a single one, Word's multiple hanging below the foot like the leading.)
               Self._needs(_heights[i], after, pst.lineSpacing) > contentH - emptyBegins + 0.01, !_pageBreak[i] {
                var k = i
                while k < count, _cells[k] == nil, document.paragraphs[k].text.isEmpty { k += 1 }
                if k < count, _cells[k] != nil, Self._followsFloatingTable(k, _cells[k]!.table, document: document, cells: _cells) {
                    RuleTrace.hit("compat14-empty-between-floating-tables-carries-with-its-space-after")
                    newPage()
                }
            }
            if _cells[i] == nil, document.paragraphs[i].text.isEmpty { lastEmptyAt = (i, page, y) }
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
            if theme.wordRules, _pageBreak[i], document.paragraphs[i].style.breakEndsPrevious, !document.paragraphs[i].style.pageBreakInline,
               resumeCursor == nil, page > 0, i > 1, document.paragraphs[i - 1].text.isEmpty, document.paragraphs[i - 1].cell == nil,
               document.paragraphs[i - 2].cell != nil,
               _pages[page].count == 1, let was = _pages[page].first, was.paragraph == i - 1, was.pageY < 0.01,
               // (Where the table reached the foot or all but a point or two
               // of it, not a quarter of the line short: lab brk, zh-0aac9d1a's
               // page 7, a table 3.4pt above the foot in Word's print and in
               // ours, and Word gives the break's 31.2pt line page 8, a blank
               // one; zh-60c80728's page 25 table ends 1.3pt above it in both,
               // and Word keeps the break there.)
               prevContentH - prevY < _px(2.5),
               let at = _allPieces.lastIndex(where: { $0.paragraph == i - 1 && $0.page == page }) {
                var only = PagePiece(paragraph: was.paragraph, flowTop: was.flowTop, flowBottom: was.flowBottom, page: page - 1, pageY: contentH)
                only.part = was.part
                _pages[page].removeAll()
                _pages[page - 1].append(only)
                _allPieces[at] = only
                y = 0
                pageFresh = true
                markOnPage = false
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
            if theme.wordRules, _pageBreak[i], document.paragraphs[i].style.breakEndsPrevious, !document.paragraphs[i].style.pageBreakInline,
               resumeCursor == nil, page > 0, i > 0, !_pageBreak[i - 1], case let before = document.paragraphs[i - 1], before.cell == nil,
               before.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC }),
               before.image.map({ $0.float != nil }) ?? !before.inlineImages.isEmpty,
               before.inlineImages.values.allSatisfy({ $0.float != nil }),
               case let after = document.paragraphs[i], !after.text.isEmpty || !after.inlineImages.isEmpty || after.image != nil,
               _pages[page].count == 1, let was = _pages[page].first, was.paragraph == i - 1, was.pageY < 0.01,
               let at = _allPieces.lastIndex(where: { $0.paragraph == i - 1 && $0.page == page }) {
                var only = PagePiece(paragraph: was.paragraph, flowTop: was.flowTop, flowBottom: was.flowBottom, page: page - 1, pageY: contentH)
                only.part = was.part
                _pages[page].removeAll()
                _pages[page - 1].append(only)
                _allPieces[at] = only
                y = 0
                pageFresh = true
                markOnPage = false
            }
            // Columns balanced at a continuous section break: Word sets
            // the section before it in columns of even length on the page
            // the break is on, and the next section under them. zh-b5359de4
            // p4: the preface's last lines stand half in each column in
            // Word's print, its contents under them, 44.3pt higher than
            // ours, which filled the first column and went on in the second.
            // (Plain paragraphs only: no table rows, no notes on the page.)
            let nb = _perSection && i > 0 ? _columnsOf(paragraph: i - 1) : _columns
            var balancedHere = false
            if theme.wordRules, nb > 1, !(_perSection && document.leavesColumnsUnbalanced), !_pageBreak[i], i > 0, i < _sectionOf.count, _sectionOf[i] != _sectionOf[i - 1],
               _cells[i] == nil, resumeCursor == nil, !notesOn || pageNotes.isEmpty {
                let first = (page / _columns) * _columns
                var seq: [PagePiece] = []
                // (Through the last column of the page, not just the one being set:
                // an earlier section's balanced block stands in all of them —
                // tdf139336's second three-column section, under the first's.)
                let lastPage = max(page, min(first + _columns - 1, _pages.count - 1))
                for s in first ... lastPage { seq += _pages[s] }
                // (A section that began partway down the page balances its
                // own pieces, under those of the sections above it.)
                var head: [PagePiece] = []
                if _perSection, let before = seq.first.map({ _sectionOf[$0.paragraph] }), before != _sectionOf[i - 1] {
                    head = seq.filter { _sectionOf[$0.paragraph] != _sectionOf[i - 1] }
                }
                let base = head.map { $0.pageY + $0.height }.max() ?? 0
                // (A table of one column in the block is its rows, set one under
                // another like paragraphs: they part between the columns as
                // paragraphs do. lo-eb12e7d4 p15's 6.1.1-6.1.3 rows, over the
                // columns' even length in Word's print.)
                let wide = Set(seq.compactMap { _cells[$0.paragraph] }.filter { $0.column > 0 || $0.span > 1 }.map(\.table))
                let oneColumnTables = Set(seq.compactMap { _cells[$0.paragraph]?.table }).subtracting(wide)
                let tail = Array(_allPieces.suffix(seq.count))
                if seq.count > head.count, tail == seq || Set(tail.map(\.paragraph)) == Set(seq.map(\.paragraph)),
                   seq.allSatisfy({ head.contains($0) || ((_cells[$0.paragraph].map { document.tableStyles[$0.table]?.floatsOverText == true || oneColumnTables.contains($0.table) } ?? true) && !$0.repeated && $0.part == .all) }) {
                    // (A floating table in the block stands where it is, a band the
                    // columns run around: lo-a998edda's A1–A4 in two columns are 2
                    // and 2 in Word's print, the table across both, the fourth
                    // line under it.)
                    let bands = seq.filter { _cells[$0.paragraph] != nil && !oneColumnTables.contains(_cells[$0.paragraph]!.table) }
                    let total = (first ... lastPage).reduce(0.0) { acc, s in acc + ((_pages[s].filter { p in !head.contains(where: { $0 == p }) }).map { $0.pageY + $0.height }.max().map { $0 - base } ?? 0) }
                    let target = total / Double(nb)
                    var out: [[PagePiece]] = Array(repeating: [], count: nb)
                    var c = 0, cy = 0.0
                    var lastBottom: [Int: Double] = [:]
                    for piece in seq where !head.contains(where: { $0 == piece }) && (_cells[piece.paragraph] == nil || oneColumnTables.contains(_cells[piece.paragraph]!.table)) {
                        let gap = max(0, piece.pageY - (lastBottom[piece.page] ?? base))
                        lastBottom[piece.page] = piece.pageY + piece.height
                        var top = cy > 0.01 ? cy + gap : 0
                        var rest = (from: piece.flowTop, to: piece.flowBottom)
                        if !bands.isEmpty, theme.wordRules {
                            let h = rest.to - rest.from
                            for band in bands.sorted(by: { $0.pageY < $1.pageY }) where top + base + h > band.pageY + 0.01 && top + base < band.pageY + band.height - 0.01 {
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
                               base + top + (rest.to - rest.from) <= contentH + 0.01 {
                                RuleTrace.hit("column-balance-ends-after-the-whole-paragraph")
                                out[c].append(PagePiece(paragraph: piece.paragraph, flowTop: rest.from, flowBottom: rest.to, page: first + c, pageY: base + top))
                                c += 1; cy = 0
                                break
                            }
                            if let cut = cuts.first(where: { top + ($0 - rest.from) >= target - 0.5 }) ?? cuts.last,
                               base + top + (cut - rest.from) <= contentH + 0.01 {
                                // (At its last line the paragraph ends here, the
                                // space under that line with it: zh-b5359de4's empty
                                // 36pt cover paragraphs, a line of 54.2 in 62.2, sent
                                // that 8pt on as a piece and the next column started
                                // under it.)
                                if let lastLine = bottoms.last, abs(cut - lastLine) < 0.01,
                                   base + top + (rest.to - rest.from) <= contentH + 0.01 {
                                    out[c].append(PagePiece(paragraph: piece.paragraph, flowTop: rest.from, flowBottom: rest.to, page: first + c, pageY: base + top))
                                    c += 1; cy = 0
                                    break
                                }
                                out[c].append(PagePiece(paragraph: piece.paragraph, flowTop: rest.from, flowBottom: cut, page: first + c, pageY: base + top))
                                rest = (cut, rest.to)
                            } else if top < 0.01 || ((_perSection || !bands.isEmpty) && top < target - 0.5) {
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
                    out[0] += head.isEmpty ? bands : bands.filter { b in !head.contains(where: { $0 == b }) }
                    let blockBottom = out.map { $0.map { $0.pageY + $0.height }.max() ?? 0 }.max() ?? 0
                    if blockBottom <= contentH + 0.01 {
                        _allPieces.removeLast(seq.count)
                        while _pages.count < first + _columns { _pages.append([]) }
                        for k in 0 ..< nb where first + k <= max(page, first + _columns - 1) { _pages[first + k] = head.filter { $0.page == first + k } + out[k] }
                        _allPieces.append(contentsOf: (head + out.flatMap { $0 }).sorted { ($0.paragraph, $0.flowTop) < ($1.paragraph, $1.flowTop) })
                        page = first
                        y = blockBottom
                        columnFloor = (first / _columns, blockBottom)
                        balancedHere = true
                    }
                }
            }
            // (A section of fewer columns than the slot it would continue in,
            // when the columns above were not balanced: it starts on the
            // next page's first column, never in a later column slot, where
            // it would paint a column to the right.)
            if _perSection, theme.wordRules, !balancedHere, i > 0, i < _sectionOf.count, _sectionOf[i] != _sectionOf[i - 1],
               resumeCursor == nil, _columnsOf(paragraph: i) < _columns, page % _columns >= _columnsOf(paragraph: i),
     _setup(ofParagraph: i - 1).columnSpec != nil {   // unequal columns only: a later slot there paints off the page; equal ones continue in the slot
                repeat { newPage() } while page % _columns >= _columnsOf(paragraph: i)
            }
            // (A section of columns that starts partway down a page: its
            // columns start there, the second under the first's top, not
            // at the page's.)
            if _perSection, theme.wordRules, !balancedHere, !_pageBreak[i], i > 0, i < _sectionOf.count, _sectionOf[i] != _sectionOf[i - 1],
               _columnsOf(paragraph: i) > 1, y > 0.01, resumeCursor == nil, page % _columns == 0 {
                columnFloor = (page / _columns, y)
            }
            // (A page break that opens the document's first paragraph is a
            // blank first page in Word: LibreOffice's
            // tdf153964_topMarginAfterBreak14 prints six pages for four of
            // ours. The paragraph property of the same name does nothing
            // there, which is why only the break inside the paragraph counts.)
            let opensTheDocument = theme.wordRules && RichTextTheme.wordWindowsPages && i == 0 && page == 0
                && document.paragraphs[i].style.pageBreakInline && !document.paragraphs[i].style.columnBreak
            if _pageBreak[i] && !sectionBreakHandled && !breakIsTheSections && (y > 0 || !_pages[page].isEmpty || markOnPage || opensTheDocument) && resumeCursor == nil {
                // (A page the line before hung past the foot of has no
                // room for the break's own line: that line takes a page
                // of its own, and the break ends that one too — a blank
                // page. Lab `gf` replayed in Word for Windows, 2026-10-14:
                // a 16pt line on 36pt of grid kept 31.75 to 35pt above the
                // foot, then "[break]测试", sets 测试 on page 3; with 36pt
                // left, on page 2. zh-6d1afa56's empty page 23.)
                if theme.wordRules, document.paragraphs[i].style.pageBreakInline, !document.paragraphs[i].style.columnBreak,
                   overfull || (y > contentH + 0.01 && spacedPast.map { abs($0 - y) > 0.01 } ?? true) {
                    newPage()
                }
                newPage()
                // (In columns a page break, or a section's, goes on to the
                // next page, not the next column: only a column break
                // does that. zh-b5359de4's preface section, after a cover
                // that runs into page 2's first column, opens Word's page
                // 3; ours set it in page 2's second column and went on a
                // column ahead of Word's.)
                if theme.wordRules, _columns > 1, !document.paragraphs[i].style.columnBreak {
                    while page % _columns != 0 { newPage() }
                }
                if theme.wordRules, document.paragraphs[i].style.pageBreakTwice { newPage() }
            }
            // A float that bands its page (`ImageFloat.bandsPage`): the text
            // keeps off it, and what of the page's text before its anchor
            // reaches into it goes under it, as under a table placed on the
            // page. (After the paragraph's own break: zh-fe536967's
            // photo is anchored at a section's start.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, resumeCursor == nil, _columns > 1, y > 0.01, _cells[i] == nil, _columnPushed.contains(i) { newPage() }
            // (A column's anchor paragraph whose own band, at the column's
            // top, would push the column's text down until the paragraph no
            // longer fits goes to the next column with its band: Word never
            // shows the picture where its paragraph is not. LibreOffice's
            // fdo43573-2-min, page 8: a 3-line paragraph at the foot of
            // column 2 anchors an 87x35pt picture 2.1pt under the top
            // margin; Word sets the paragraph and the picture on page 9,
            // ours set the picture over page 8's column and the paragraph
            // under it.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, resumeCursor == nil, _columns > 1, _cells[i] == nil, deferredUnder.isEmpty, y > 0.01,
               !document.paragraphs[i].text.isEmpty {
                let own = (i < _floatImages.count ? _floatImages[i].map { [$0] } ?? [] : []) + (i < _inline.count ? _inline[i] : [])
                let physical = page / _columns
                let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
                var bandBottom = 0.0
                for image in own {
                    guard let f = image.float, f.bandsPage, f.verticalFrom != "paragraph", f.verticalAlign == nil, image.height > 0 else { continue }
                    let onPage = _px(f.y) - (f.verticalFrom == "margin" ? 0 : insetTop)
                    let top = onPage - _px(f.distanceTop)
                    if top <= _px(8) { bandBottom = max(bandBottom, onPage + _px(image.height + f.distanceBottom)) }
                }
                if bandBottom > 0, bandBottom <= contentH / 2, let first = _pages[page].first(where: { _cells[$0.paragraph] == nil && !$0.repeated }), first.pageY < bandBottom {
                    let bottoms = Self._lineBottoms(geometry(i).painter)
                    let need = bottoms.count <= 3 ? (bottoms.last ?? 0) : (bottoms.count >= 2 ? bottoms[1] : (bottoms.first ?? 0))
                    let colEnd = _pages[page].last.map { $0.pageY + $0.flowBottom - $0.flowTop } ?? y
                    if colEnd + (bandBottom - first.pageY) + need > contentH + 0.01 {
                        // (Word's prints, six variants of the document: the column before then
                        // loses its last paragraph to this one's top — "L (links) = geel" —
                        // when the paragraph and its picture were sent on; not when the picture
                        // is absent, or the paragraph still fits its first line.)
                        if !pinPass, page % _columns > 0, let prev = _pages[page - 1].last, !prev.repeated, _cells[prev.paragraph] == nil,
                           !_columnPushed.contains(prev.paragraph), _allPieces.filter({ $0.paragraph == prev.paragraph }).count == 1 {
                            _columnPushed.insert(prev.paragraph)
                            pushedAnew = true
                        }
                        newPage()
                    }
                }
            }
            if theme.wordRules, resumeCursor == nil, _cells[i] == nil, deferredUnder.isEmpty {
                let images = (i < _floatImages.count ? _floatImages[i].map { [$0] } ?? [] : []) + (i < _inline.count ? _inline[i] : [])
                for image in images {
                    // (A picture centred in its column, wrapped on both sides, with room at each side for less than
                    // three ems: the text of a later paragraph whose first unit does not fit at either side stands
                    // under it. Word's lab capwrap: a caption opening with a bracket sets nothing beside the picture
                    // at any gap, one opening with an ideograph sets one ideograph a row on each side only while it
                    // fits, and a line starts at the left piece: where its first unit does not fit there it goes under, as in 817e3a79's caption (room 32.2 each side, first line indented 32); the first line clear of the picture is the next row of the page's own pitch.)
                    if theme.wordRules, RichTextTheme.wordWindowsPages, let f = image.float, f.wraps, !f.takesRoom, f.wrapSide == nil,
                       f.verticalFrom == "paragraph", f.verticalAlign == nil, f.horizontalAlign == "center", f.horizontalFrom == "column",
                       _cells[i] == nil, image.width > 0, image.height > 0 {
                        let inner = _flowWidth(i), w = _px(image.width), x = (inner - w) / 2
                        let l = x - _px(f.distanceLeft ?? 9), r = inner - (x + w) - _px(f.distanceRight ?? 9)
                        let top = y + _px(f.y) - _px(f.distanceTop), bottom = y + _px(f.y) + _px(image.height + f.effectBottom + f.distanceBottom)
                        narrowBands.removeAll(where: { $0.owner >= i })
                        if bottom > top, bottom > 0.01 { narrowBands.append((top, bottom, i, l, r)) }
                    }
                    guard let f = image.float, f.bandsPage else { continue }
                    let physical = page / _columns
                    let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
                    let mine = f.verticalFrom == "paragraph"
                    // (The paragraph after one that an earlier float's band pushed down stands under the band
                    // too, and its own box, set top and bottom from it, is measured from where the pushed
                    // paragraph would have stood: Word's print of dx2 87097d3e puts the third chart, 364.5pt
                    // from its paragraph, at 471 under the second chart's band, not 364.5pt below the pushed line.)
                    var carried = 0.0
                    if RichTextTheme.wordWindowsPages, mine, f.verticalAlign == nil, bandPushLast == i - 1, bandPushPage == page, bandPushDelta > 0.01, _cells[i] == nil {
                        carried = max(bandPushDelta, y - bandPushTop)
                        RuleTrace.hit("word-paragraph-after-a-pushed-one-keeps-its-box-at-the-unpushed-anchor")
                        _floatShiftY[image.id] = -carried
                        bandPushLast = i
                    }
                    let onPage = mine ? y - carried + _px(f.y) : _px(f.y) - (f.verticalFrom == "margin" ? 0 : insetTop)
                    let top = onPage - _px(f.distanceTop), bottom = onPage + _px(image.height + f.distanceBottom)
                    guard bottom > 0.01, top < contentH - 0.01, !(mine && image.height <= 0) else { continue }
                    // (Its own paragraph keeps its place: the band is under
                    // what follows it, as the title over zh-6d402586's box.)
                    tableBands.append((top: top, bottom: bottom, owner: mine ? i : -1))
                    var moved: [PagePiece] = []
                    // (A hair above its own line, -0.9pt as in lo-eb12e7d4's 137pt picture: the
                    // line before it is not under the picture — Word sets it where it stood and
                    // the picture after it, at the paragraph's first place.)
                    let moveTop = mine && RichTextTheme.wordWindowsPages && f.y < -0.3 && f.y > -2 ? max(top, y) : top
                    while let last = _pages[page].last, last.paragraph < i, _cells[last.paragraph] == nil, !last.repeated,
                          last.pageY + (last.flowBottom - last.flowTop) > moveTop + 0.01 {
                        moved.insert(_pages[page].removeLast(), at: 0)
                        if let k = _allPieces.lastIndex(of: moved[0]) { _allPieces.remove(at: k) }
                        if last.pageY <= moveTop + 0.01 { break }
                    }
                    if !moved.isEmpty {
                        reordered = true
                        y = max(top, bottom)
                        deferredUnder = moved
                        placeDeferred()
                    } else if !(mine && RichTextTheme.wordWindowsPages), y > top - 0.01, y < bottom {
                        // (Not its own paragraph, with the float at its top: the line goes under the
                        // float, the paragraph stays — LibreOffice's tdf137850, a text box wrapped
                        // top and bottom at offset 0, stands at the margin in Word's print, not
                        // under its own height.)
                        y = bottom
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
            if theme.wordRules, document.evenAndOddHeaders, _columns == 1, resumeCursor == nil, i > 0, page > 0,
               y < 0.01, _pages[page].isEmpty, i < _sectionOf.count, _sectionOf[i] != _sectionOf[i - 1],
               let first = _sectionNumberStart(_sectionOf[i], document),
               (first - _pageNumberOf(page - 1, document)) % 2 == 0 {
                _blankPages.insert(page)
                newPage()
            }
            if endsSection { markOnPage = true }
            // (A paragraph under a table whose header was left off a page
            // for want of room stands as if it were there: its height still
            // counts, and the paragraph goes to the next page when it would
            // not fit under it — lo Cool16066: "END OF DOCUMENT" under the
            // 40-line row at page 2's top, 14pt of text with 169pt left, is
            // page 3's only line in Word's print.)
            if theme.wordRules, i > 0, _cells[i] == nil, resumeCursor == nil, y > 0.01, let before = _cells[i - 1],
               let head = omittedHeadHeight[before.table], y + head > contentH + 0.01 {
                newPage()
            }
            // The document's final empty paragraph under a table that has
            // reached its third page goes to a page of its own, whatever room
            // is left (a table ending on its second page keeps it beside it):
            // Word's lab prints of lo-28f9b886 (amd-5 lab A).
            if theme.wordRules, RichTextTheme.wordWindowsPages, i > 0, i == document.paragraphs.count - 1, _cells[i] == nil,
               resumeCursor == nil, y > 0.01, document.paragraphs[i].text.isEmpty, let before = _cells[i - 1], headerRows(before.table) > 0, let first = _tableFirstParagraph[before.table],
               // (… with repeated header rows over a quarter of the page: the lab's two, 213pt, made the table
               // reach its third page; the 90 long tables of the corpus with a one-line header keep it beside them.)
               case let headTop = _cells[first]?.rowTop ?? 0,
               (first ..< i).reduce(0.0, { acc, k in
                   guard let d = _cells[k], d.table == before.table, d.row < headerRows(before.table) else { return acc }
                   return max(acc, d.rowTop + d.ownRowHeight - headTop)
               }) > contentH * 0.25,
               (0 ... page).filter({ pg in _pages[pg].contains(where: { _cells[$0.paragraph]?.table == before.table && !$0.repeated }) }).count >= 3 {
                newPage()
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
            if theme.wordRules, resumeCursor == nil, y > 0.01, document.paragraphs[i].style.keepNext,
               // (A table's row whose text keeps with the next carries
               // the run through: bug65649's place-and-date table.)
               !(i > 0 && document.paragraphs[i - 1].style.keepNext) {
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
                        if theme.wordRules, let ts = document.tableStyles[c.table], ts.headerRow, c.row < ts.headerRowCount, c.ownRowHeight <= contentH + 0.01 {
                            RuleTrace.hit("word-kept-heading-asks-the-whole-header-row")
                            return c.ownRowHeight
                        }
                        guard theme.wordRules, document.tableStyles[c.table]?.rowsCantSplit.contains(c.row) != true,
                              !(document.tableStyles[c.table]?.rowsExactHeight.contains(c.row) == true && c.ownRowHeight <= contentH + 0.01) else { return c.ownRowHeight }
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
                        if trailing, bottoms.count <= 1, theme.wordRules, pageNotes.isEmpty, k < _overhang.count {
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
                    var reach = theme.wordRules && pageNotes.isEmpty && k < _overhang.count ? _overhang[k] : 0
                    if theme.wordRules, pageNotes.isEmpty, k < _lineOverhang.count, n < _lineOverhang[k].count { reach = max(reach, _lineOverhang[k][n]) }
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
                let sharedNow = i > 0 && _cells[i - 1] == nil ? min(y, max(0, _tops[i - 1] + _heights[i - 1] - top)) : 0
                func weigh(_ room: Double) -> Bool {
                var cum = 0.0
                var k = i
                var violated = false
                var ended = false   // the run ends with a section: nothing is kept across its break
                while k < count, _cells[k] == nil, document.paragraphs[k].style.keepNext {
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
                    violated = k > i ? cum + start(k) > room + 0.01
                        : _cells[i] == nil && whole(i) && _heights[i] <= contentH + 0.01
                            && (start(i) > room + 0.01 || (i + 1 < count && document.paragraphs[i].style.sectionXML == nil))
                    break
                }
                if !violated, !ended, k < count, k > i, (_cells[k] != nil || !document.paragraphs[k].style.keepNext) {
                    let single = k == i + 1 && _cells[k] == nil && !document.paragraphs[k].style.keepNext
                    violated = cum + start(k, trailing: single) > room + (single ? sharedNow : 0) + 0.01
                }
                    return violated
                }
                var violated = weigh(contentH - y)
                if violated {
                    newPage()
                    // (The run weighed again where it landed: sent into a
                    // column that cannot hold it either, it goes on to the
                    // next page, as in Word's print of lab col2flow, where
                    // "目录" and the two kept empties above it open page 3
                    // and ours left 152pt of column 1 empty above them.)
                    if theme.wordRules, _columns > 1, page % _columns != 0, weigh(contentH - y) {
                        while page % _columns != 0 { newPage() }
                    }
                }
            }
            // The space it shares with the paragraph above (`_sharedSpace`)
            // is on the page once, as it is in the flow.
            if i > 0, _cells[i - 1] == nil, y > 0.01, resumeCursor == nil {
                y -= min(y, max(0, _tops[i - 1] + _heights[i - 1] - top))
            }
            // (Whether a page's head takes this paragraph's space before
            // off — see where the paragraph is set.)
            // (A box's top line and the room under it stay: lab bdr2, b2, BBB's 40pt before
            // goes at the page's top and its box opens there, text 7pt under it.)
            let boxRoom = theme.wordRules && RichTextTheme.wordWindowsPages && (document.compatibilityMode ?? 12) >= 14 && (document.paragraphs[i].style.continuesParagraph || document.paragraphs[i].style.pageBreakInline || !_pageBreak[i] || _afterBareBreak(i, document)) && !_bordersJoin(i - 1, i, document) && !_emptyBreakFragment(i, document)
                ? document.paragraphs[i].style.borders?.top.map { _px($0.space + Self._ruleRoom($0.style, $0.width)) } ?? 0 : 0
            let lead = i < _floatPush.count ? max(0, _spaceBefore[i] - _floatPush[i] - boxRoom) : 0
            var leavesLead = false
            if theme.wordRules, lead > 0.01, (resumeCursor ?? top) <= top + 0.01 {
                let st = document.paragraphs[i].style
                // (A section's first paragraph that opens with a column break
                // loses it all the same: zh-b8de3ae2 p15, 3pt, compat 15.)
                let newSection = i > 0 && document.paragraphs[i - 1].style.sectionXML != nil && !(st.columnBreak && (document.compatibilityMode ?? 12) >= 15)
                let ownBreak = _pageBreak[i] && !st.pageBreakInline && !st.breakEndsPrevious
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
                if leavesLead, st.markFollowsBreak { leavesLead = false; RuleTrace.hit("word-split-break-mark-keeps-its-space-before") }
            }
            // How much of it a page's head takes off, for where a line
            // under a float first stands (below): zh-27a874b7's chart
            // anchor opens a section under the last one's 9pt after, so
            // its 9pt before goes and its line stands over the chart;
            // zh-d62da4dd's, under none, keeps it, and the line goes
            // under (lab t3d, Word for Windows).
            var headSkip = 0.0
            if theme.wordRules, y < 0.01, page > 0, lead > 0.01, (resumeCursor ?? top) <= top + 0.01 {
                if leavesLead { headSkip = pageFresh ? lead : 0 }
                else if i > 0, _cells[i - 1] == nil, !document.paragraphs[i].style.markFollowsBreak { headSkip = min(lead, _spacing(i - 1, document).after) }
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
            if theme.wordRules, resumeCursor == nil, _cells[i] == nil {
                let column = _flowWidth(i)
                let gap = _px(9)
                // (An empty paragraph — or one of floating objects' places
                // alone — asks half an em: zh-d62da4dd's empty paragraphs
                // stand in the 10.95pt a tight-wrapped chart leaves at the
                // column's left in Word's print (12pt); zh-37b6536f's under
                // its row of photos, which leaves 5.0, go under it.)
                let bare = document.paragraphs[i].text.unicodeScalars.allSatisfy { $0.value == 0xFFFC || $0 == " " }
                // (A list paragraph's first line asks its label's room as well,
                // and starts at the label: zh-f2ca3070's "二、 共同工作空間",
                // its label slot 27pt, starting 21pt in, has 24pt left of a
                // tight-wrapped price list and 38 right of it, and Word sets
                // it under the picture — a line that meets the picture's top
                // 5pt down, its own top above it.)
                let listed = !bare && RichTextTheme.wordWindowsPages ? _listIndents(document.paragraphs[i], document) : nil
                let label = listed.map { _px($0.hanging) } ?? 0
                let lineStart = listed.map { max(0, _px($0.left - $0.hanging)) } ?? 0
                let em = _px(document.paragraphs[i].runs.first?.style.fontSize ?? theme.fontSize) * (bare ? 0.5 : 1) + label
                // (Over any of the line, not only its top: an empty
                // anchor's line that a photo starts 16pt down went under
                // the photo in Word's print.)
                func noRoom(at at: Double, height: Double = 0, _ extra: [(top: Double, bottom: Double, left: Double, right: Double)]) -> Double? {
                    let over = (bands + extra).filter { $0.top < at + max(0.02, height) - 0.01 && $0.bottom > at + 0.01 }
                    guard !over.isEmpty else { return nil }
                    // The widest stretch of the column no picture covers.
                    var spans = over.map { (max(0, $0.left - gap), min(column, $0.right + gap)) }.sorted { $0.0 < $1.0 }
                    var widest = 0.0, edge = lineStart
                    for s in spans { widest = max(widest, s.0 - edge); edge = max(edge, s.1) }
                    widest = max(widest, column - edge)
                    spans.removeAll()
                    return widest < em ? over.map(\.bottom).min() : nil
                }
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
                let keepsOwnPicture = theme.wordRules && RichTextTheme.wordWindowsPages && _anchorsOnly(i, document)
                    && document.paragraphs[i].style.lineSpacing > 1.001 && document.paragraphs[i].style.lineHeightPoints == nil
                    && document.paragraphs[i].image?.float.map { $0.wraps && !$0.takesRoom && !$0.bandsPage && $0.verticalFrom == "paragraph" } == true
                if theme.wordRules, !keepsOwnPicture, i < _floatPush.count, _floatPush[i] < 0.01, noRoom(at: y, []) != nil,
                   let line = Self._lineBottoms(geometry(i).painter).first,
                   case let step = lead + line - _firstLineGridHalf(i, document), step > 1 {
                    var t = y + lead - headSkip
                    while let below = noRoom(at: t, []), guardSteps < 20 {
                        t += max(1, ((below - t) / step - 0.001).rounded(.up)) * step
                        guardSteps += 1
                    }
                    y = max(y, t - lead)
                } else {
                    // (In Word for Windows, over any of the first line: zh-e51c31a7's
                    // "以下欄位由交通部填寫" starts 1.3pt above the foot-wide
                    // form box (外框1, 511pt, wrapped square, 14.35pt under its
                    // anchor's top) and stands under the box in Word's print,
                    // its table after it; ours set it under the box's top, the
                    // two drawn over each other. Word for Mac sets it there, as
                    // ours did.)
                    let reach = RichTextTheme.wordWindowsPages
                        ? (Self._lineBottoms(geometry(i).painter).first.map { $0 + (geometry(i).textTop - geometry(i).top) } ?? 0) : 0
                    // (A list paragraph's whole first line meets the picture, and
                    // steps a line and its space before at a time, as Word does:
                    // zh-f2ca3070's heading, first at 285, stands at 376.7 under a
                    // picture ending 361.8, 4 steps of 23.)
                    let firstHeight = label > 0 ? (Self._lineBottoms(geometry(i).painter).first ?? 0) : 0
                    if label > 0, firstHeight + lead > 1 {
                        let step = firstHeight + lead
                        while let below = noRoom(at: y + lead, height: firstHeight, []), guardSteps < 20 {
                            y += max(1, ((below - y - lead) / step - 0.001).rounded(.up)) * step
                            guardSteps += 1
                        }
                    } else if !keepsOwnPicture {
                        let stoodAt = y
                        while let below = noRoom(at: y, height: reach, []), guardSteps < 20 { y = below; guardSteps += 1 }
                        // (What meets the box is the paragraph, its space before
                        // and all, and what stands clear of it is the LINE: Word's
                        // print of lo-61f8f967 (para-upper-margin-fly-intersect,
                        // 28.35pt before) sets the second paragraph's line at the
                        // wrapSquare box's foot, 172 (170.25 and the line's ascent),
                        // its space before overlapping the box; ours set it that
                        // far again lower, at 199.)
                        if theme.wordRules, RichTextTheme.wordWindowsPages, y > stoodAt + 0.01, lead > 0.01 {
                            RuleTrace.hit("word-box-pushed-paragraph-stands-its-line-at-the-foot")
                            y = max(stoodAt, y - lead)
                        }
                    }
                }
                // (A table placed down the page keeps the whole of a line
                // off it, not only the line's top: zh-10eab555's contents
                // line 17, which would reach into the issuing table, goes
                // under it — and so to page 3 — in Word's print.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, !narrowBands.isEmpty, _cells[i] == nil, !document.paragraphs[i].text.isEmpty {
                    let q = document.paragraphs[i]
                    let size = _px(q.runs.first?.style.fontSize ?? theme.fontSize)
                    let opens = q.text.first.map { "（(【《「『〈［｛".contains($0) } ?? false
                    let unit = size * (opens ? 2 : 1)
                    let first = q.style.indentLeft + max(0, firstLineIndent(q, document))
                    let lineBottoms = Self._lineBottoms(geometry(i).painter)
                    let step = (lineBottoms.first ?? _heights[i]) + (geometry(i).textTop - geometry(i).top)
                    var guardNarrow = 0
                    while step > 0.5, guardNarrow < 40,
                          let band = narrowBands.first(where: { $0.owner < i && $0.top < y + step - 0.01 && $0.bottom > y + 0.01 && $0.left - _px(first) < unit }) {
                        RuleTrace.hit("word-line-with-no-room-beside-a-centred-picture-stands-under-it")
                        y += max(1, ((band.bottom - y) / step - 0.001).rounded(.up)) * step
                        guardNarrow += 1
                    }
                }
                var pushedByTableBand = false
                if !tableBands.isEmpty {
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
                    let style = document.paragraphs[i].style
                    let lineBottoms = Self._lineBottoms(geometry(i).painter)
                    let gridHalf = lineBottoms.count == 1 && style.lineHeightPoints == nil
                        && style.eastAsian["w:snapToGrid"] != "0" && _grid(i, document).pitch != nil
                        && i < _overhang.count ? _overhang[i] : 0
                    // (A paragraph that anchors a float of its own stands its line
                    // by the line alone: its box reaches down over the float, and
                    // the float is not a text line to keep off an earlier band —
                    // lo's c4c60fcb, a chart group anchored in an empty line above
                    // a text box's band, went to the next page.)
                    let ownsBand = tableBands.contains { $0.owner == i }
                    let line = (lineBottoms.first.map { $0 + (ownsBand ? 0 : geometry(i).textTop - geometry(i).top) } ?? _heights[i]) - gridHalf
                    let yBeforeBands = y
                    while let band = tableBands.first(where: { $0.owner != i && $0.top < y + line - 0.01 && $0.bottom > y + 0.01 }), guardSteps < 40 {
                        // (In a column that is not the last, what meets a picture wrapped top and
                        // bottom that an earlier paragraph of text anchors in the column goes on in the
                        // next column, not under the picture: lab f43/g43 (Word for Windows,
                        // lo-eb12e7d4's p13) — 4.3 stands at column 2's top with the picture
                        // up to 72pt higher and 95pt of column 1 free under it, and a line of
                        // 4.2 the picture would be over goes with it.)
                        if theme.wordRules, RichTextTheme.wordWindowsPages, _columns > 1, page % _columns < _columns - 1,
                           band.owner >= 0, band.owner < i, !_anchorsOnly(band.owner, document), resumeCursor == nil, y > 0.01 {
                            RuleTrace.hit("word-column-text-meeting-a-band-goes-to-the-next-column")
                            newPage()
                            break
                        }
                        y = band.bottom; guardSteps += 1
                        if band.owner < 0 { pushedByTableBand = true }
                    }
                    if pushedByTableBand { y -= _tableBandSharedSpace(i, document) }
                    if theme.wordRules, y > yBeforeBands + 0.01, _cells[i] == nil { bandPushLast = i; bandPushDelta = y - yBeforeBands; bandPushPage = page; bandPushTop = yBeforeBands - lead }
                    // (A paragraph, with text or not, that sets a box top and bottom from itself and goes under an earlier
                    // box's band keeps its box at the place it stood before: Word's lab ttb 1-4 print the second
                    // box at 97 + 300, the line at 344 under the first; ours drew it at 344 + 300.)
                    if theme.wordRules, RichTextTheme.wordWindowsPages, ownsBand, y > yBeforeBands + 0.01, _cells[i] == nil {
                        for image in (i < _floatImages.count ? _floatImages[i].map { [$0] } ?? [] : []) + (i < _inline.count ? _inline[i] : []) {
                            guard let f = image.float, f.bandsPage, f.verticalFrom == "paragraph", f.verticalAlign == nil else { continue }
                            RuleTrace.hit("word-empty-paragraph-under-a-band-keeps-its-own-box-at-the-unpushed-anchor")
                            _floatShiftY[image.id] = -(y - yBeforeBands)
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
                let ender = theme.wordRules && _heights[i] == 0 && document.paragraphs[i].style.sectionXML != nil
                    && document.paragraphs[i].cell == nil && document.paragraphs[i].text.isEmpty
                if y > contentH - 0.01, !ender { newPage() }
                // (An empty paragraph at a column's foot, the paragraph after it too long for what
                // is left, and a table next whose cell holds a picture wrapped top and bottom: Word's
                // print carries the empty paragraph to the top of the next column with them — lab
                // ef4/ef5, from lo-eb12e7d4's page 14, where it moved only with that picture, not a
                // square-wrapped or an inline one, and the column after it stood 17pt lower. Only seen with the table
                // exactly two paragraphs on, and the paragraph between them: the labs did not try a gap of two or a keep-with-next chain.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, _columns > 1, y > 0.01, !ender, _cells[i] == nil,
                   document.paragraphs[i].text.isEmpty, document.paragraphs[i].image == nil, document.paragraphs[i].inlineImages.isEmpty,
                   i + 2 < count, _cells[i + 1] == nil, !document.paragraphs[i + 1].text.isEmpty, _cells[i + 2] != nil,
                   contentH - (y + _heights[i]) < _heights[i + 1] {
                    let table = _cells[i + 2]!.table
                    var topAndBottom = false
                    var k = i + 2
                    while k < count, let cell = _cells[k], cell.table == table, cell.row == 0 {
                        for image in Array(document.paragraphs[k].inlineImages.inOrder) + (document.paragraphs[k].image.map { [$0] } ?? []) {
                            if let float = image.float, float.takesRoom || float.bandsPage, !float.wraps { topAndBottom = true }
                        }
                        k += 1
                    }
                    if topAndBottom {
                        RuleTrace.hit("word-empty-paragraph-before-a-top-and-bottom-picture-table-goes-with-it-to-the-next-column")
                        newPage()
                    }
                }
                var mine = _wrapBoxes(i)
                for box in mine { if let dy = _floatShiftY[box.id] { _floatShiftY[box.id] = nil; let r = box.rect; mine = mine.map { $0.id == box.id ? ($0.id, Rect.fromLTWH(r.left, r.top - dy, r.width, r.height), $0.above, $0.below) : $0 } } }
                // (A box of the paragraph's own that the page fixes — a text box
                // wrapped square, placed from the page or its margin, the
                // full column wide — and that the paragraph's first line
                // meets, space before and all, sends the paragraph under it,
                // and its space before is set again there: lo tdf116486's
                // "TEST", 175pt before, its line 274 to 285 and the box 283
                // to 299, stands at 474 in Word's print, 299 + 175; ours
                // stood at 274, over the box's own text.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, _anchorsOnly(i, document) == false,
                   !document.paragraphs[i].text.isEmpty, lead > 0.01 {
                    var fixed: [(top: Double, bottom: Double, left: Double, right: Double)] = []
                    var own: [ImageAttachment] = []
                    if i < _floatImages.count, let image = _floatImages[i] { own.append(image) }
                    if i < _inline.count { own += _inline[i] }
                    for image in own {
                        guard let float = image.float, float.wraps, !float.takesRoom, float.verticalAlign == nil, float.heightShare == nil,
                              float.verticalFrom == "page" || float.verticalFrom == "margin", float.horizontalFrom != "character",
                              image.textBox != nil || !image.data.isEmpty else { continue }
                        let r = _floatRect(float, image, geometry(i), i)
                        let t = _px(float.y) - (float.verticalFrom == "page" ? _pxMarginTop(page) : 0)
                        fixed.append((t - _px(float.distanceTop), t + _px(image.height) + _px(float.distanceBottom), r.left, r.right))
                    }
                    if !fixed.isEmpty {
                        let reach = Self._lineBottoms(geometry(i).painter).first.map { $0 + (geometry(i).textTop - geometry(i).top) } ?? 0
                        let kept = bands
                        bands = []
                        var steps = 0
                        while let below = noRoom(at: y, height: reach, fixed), steps < 20, below > y + 0.01 {
                            y = below; steps += 1
                            RuleTrace.hit("word-own-fixed-box-sends-its-paragraph-under")
                        }
                        bands = kept
                    }
                }
                if !mine.isEmpty {
                    if y > 0.01, mine.contains(where: { _pinnedFloats[$0.id]?.page != page && y + $0.rect.bottom - top > contentH + 0.5 }) { newPage() }
                    var placed: [(top: Double, bottom: Double, left: Double, right: Double)] = []
                    for box in mine {
                        var r = (top: y + box.rect.top - top - box.above, bottom: y + box.rect.bottom - top + box.below, left: box.rect.left, right: box.rect.right)
                        // (Pinned: where the first setting put it, its band
                        // already on the page, drawn there however far its
                        // paragraph has moved since.)
                        if let pin = _pinnedFloats[box.id], pin.page == page {
                            let moved = y - pin.anchorY
                            _floatShiftY[box.id] = abs(moved) > 0.01 ? -moved : nil
                            continue
                        }
                        // (Found over a table's row set before its anchor
                        // on this page: a table does not wrap.)
                        if theme.wordRules, !pinPass,
                           _pages[page].contains(where: { piece in
                               !piece.repeated && piece.part != .rules && piece.paragraph < i && _cells[piece.paragraph] != nil
                                   && piece.pageY < r.bottom - 0.5 && piece.pageY + (piece.flowBottom - piece.flowTop) > r.top + 0.5
                           }) {
                            _pinnedFloats[box.id] = (page, r.top, r.bottom, r.left, r.right, y)
                            pinnedAnew = true
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
                        let ownFloat = ((i < _floatImages.count ? [_floatImages[i]].compactMap { $0 } : []) + (i < _inline.count ? _inline[i] : []))
                            .first { $0.id == box.id && ($0.sourceXML?.containsSubstring("allowOverlap=\"1\"") ?? false) }
                        let allowsOverlap = theme.wordRules && RichTextTheme.wordWindowsPages && ownFloat != nil
                        // (Only an offset the file gives, along the column: an aligned float has none to keep.)
                        let keptOffset = allowsOverlap && ownFloat?.float?.horizontalAlign == nil && ownFloat?.float?.horizontalFrom == "column"
                        for b in (allowsOverlap ? bands : bands + placed) where b.top < r.bottom - 10 && b.bottom > r.top + 10
                            && b.left < span.1 + shift - 0.5 && b.right > span.0 + shift + 0.5 && span.0 + shift < b.right {
                            // (Moved clear it lands at the other's right edge PLUS its own offset along the column: windows' overlap2.)
                            shift = max(shift, b.right - span.0 + (keptOffset ? r.left : 0))
                        }
                        // (One moved clear that would leave the page stays where it is put: lo-6f698ba2's frame, 361 to 539,
                        // over an earlier paragraph's picture in Word's print.)
                        if keptOffset, shift > 0.5, r.right + shift > pageRect(page).width - _pxMarginLeft(page) + 0.5 { shift = 0 }
                        _floatShift[box.id] = shift > 0.5 ? shift : nil
                        r.left += shift; r.right += shift
                        placed.append(r)
                    }
                    bands += placed
                }
                // Lines of picture-only paragraphs that the pictures now
                // leave no room — this one's and those just above it —
                // go under them, one after another; their pictures stay
                // where their paragraphs first stood. (Word's print of
                // zh-37b6536f: two photos anchored in two empty
                // paragraphs, the second moved clear of the first, and
                // both empty lines under the pair, the text after them.)
                if _anchorsOnly(i, document) {
                    anchorRun.append(i)
                    func lineTop(_ k: Int) -> Double? {
                        if k == i { return y + _spaceBefore[k] - headSkip }
                        guard let piece = _pages[page].last(where: { $0.paragraph == k && $0.part == .all }) else { return nil }
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
                    if let first = anchorRun.firstIndex(where: { k in lineTop(k).map { noRoom(at: $0, height: meets(k), []) != nil } ?? false }),
                       var at = lineTop(anchorRun[first]) {
                        var steps = 0
                        let started = at
                        while let below = noRoom(at: at, height: meets(anchorRun[first]), []), steps < 20 { at = below; steps += 1 }
                        // (A line that heads its page and, set under the picture, would end past
                        // the page's foot stays where it stands, as Word's print of zh-b3e8dec4's
                        // 672pt pictures: each one's page holds the picture at its anchor and
                        // the next picture's page follows — ours sent the line to the next page
                        // and drew the picture there, 600pt above it.)
                        if theme.wordRules, RichTextTheme.wordWindowsPages, started <= 0.01 + headSkip, anchorRun[first] == i,
                           at + lineHeight(i) > contentH + 0.01 {
                            at = started
                        }
                        for k in anchorRun[first...] {
                            guard let old = lineTop(k) else { continue }
                            let delta = at - old
                            at += lineHeight(k)
                            guard delta > 0.01 else { continue }
                            for image in document.paragraphs[k].inlineImages.values { _floatShiftY[image.id] = -delta }
                            if let image = document.paragraphs[k].image { _floatShiftY[image.id] = -delta }
                            if k == i {
                                // (Off the page's head, the line keeps all
                                // of its space before.)
                                y += delta - headSkip
                            } else {
                                for n in _pages[page].indices where _pages[page][n].paragraph == k {
                                    let moved = _pages[page][n]
                                    _pages[page][n] = PagePiece(paragraph: moved.paragraph, flowTop: moved.flowTop, flowBottom: moved.flowBottom,
                                                                page: moved.page, pageY: moved.pageY + delta)
                                    if let m = _allPieces.lastIndex(of: moved) { _allPieces[m] = _pages[page][n] }
                                }
                            }
                        }
                    }
                } else if !document.paragraphs[i].text.isEmpty {
                    anchorRun.removeAll()
                }
            }
            var cursor = resumeCursor ?? top
            resumeCursor = nil
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
            let ownFrame = document.paragraphs[i].style.frameXML
            let frameStarts = theme.wordRules && _cells[i] == nil && ownFrame != nil
                && !(i > 0 && document.paragraphs[i - 1].style.frameXML == ownFrame)
            // (The first paragraph of the flow after such a frame — not another
            // frame, not a table's — stands under it, or on the next page.)
            if let foot = frameFoot, ownFrame == nil, _cells[i] == nil {
                // (A frame set from the text below, of an exact height, leaves the
                // paragraphs that end over it where they are: the flow goes under
                // it from the first that would meet it.)
                if foot.top > 0, foot.page == page, i < _heights.count, y + _heights[i] <= foot.top - 0.5 {
                    // stays pending
                } else {
                    if foot.page == page { y = max(y, foot.y) }
                    frameFoot = nil
                }
            }
            // (Frames of an exact height, wrapped "notBeside" and set from the text, are
            // anchored to the paragraph after them, not to each other: lo's
            // tdf105035_framePrC sets a title frame and an authors frame, both 28.4pt
            // down, over each other, the "Abstract" line above them and the body under
            // both. Each is set where the flow stands plus its offset, and takes no
            // room; the flow goes under the lower foot from the first line that
            // would meet it.)
            if frameStarts, theme.wordRules, RichTextTheme.wordWindowsPages, let f = document.paragraphs[i].style.frame,
               f.verticalAnchor == "text", f.verticalAlign == nil, let xml = document.paragraphs[i].style.frameXML,
               xml.containsSubstring("w:wrap=\"notBeside\""), xml.containsSubstring("w:hRule=\"exact\""),
               let hAt = xml.firstRange(of: "w:h=\""), let hh = Double(xml[hAt.upperBound...].prefix { $0 != "\"" }), hh > 0,
               document.paragraphs[i].image == nil {
                var v = 0.0
                if let at = xml.firstRange(of: "w:vSpace=\""), let n = Double(xml[at.upperBound...].prefix { $0 != "\"" }) { v = n / 20 }
                let target = y + _px(f.y)
                if target < contentH - 0.01 {
                    RuleTrace.hit("exact-text-frame-hangs-from-the-flow-below-it")
                    if frameReturn == nil || frameReturn!.page != page { frameReturn = (y, page) }
                    y = target
                    let foot = target + _px(hh / 20 + v)
                    frameFoot = (max(foot, frameFoot?.page == page ? frameFoot!.y : 0), page, min(target, frameFoot?.page == page ? frameFoot!.top : target))
                }
            } else
            if frameStarts, let f = document.paragraphs[i].style.frame, Self._framePlaced(f), Self._onThePage(document.paragraphs[i].style) {
                let physical = page / _columns
                let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
                // (A frame on the margin from the text's top: the cover's
                // "山东省市场监督管理局 发布", 751pt under the margin, stood
                // in the flow at the page's head.)
                var target = f.verticalAnchor == "margin" ? _px(f.y) : _px(f.y) - insetTop
                // (Aligned on the margins, by the height it states: the
                // frame of LibreOffice's tdf112287 has yAlign bottom and
                // stands at the foot of the text area in Word's print.)
                if let a = f.verticalAlign, let h = f.height {
                    target = a == "top" ? 0 : a == "center" ? (contentH - _px(h)) / 2 : contentH - _px(h)
                }
                // (A page-anchored frame that holds one drawing in its line
                // and nothing else stands its drawing at the frame's y less
                // the page's top margin — lab frame, Word for Windows, 20
                // prints: lo tdf147485's logo, frame y 49.8, margin 27,
                // drawn from 22.8, whatever the frame's or drawing's height.)
                let framed = document.paragraphs[i]
                if theme.wordRules, f.verticalAnchor == "page",
                   framed.image.map({ $0.float == nil }) ?? (!framed.inlineImages.isEmpty && framed.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC })
                                                            && framed.inlineImages.values.allSatisfy({ $0.float == nil })) {
                    target -= insetTop
                }
                if target > -insetTop, target < contentH - 0.01 {
                    if frameReturn == nil || frameReturn!.page != page { frameReturn = (y, page) }
                    y = target
                    // (A frame text is not set beside, of a height it states
                    // exactly: the flow after it starts under it — lo
                    // tdf104394_lostTextbox's 237pt box on a 298pt page
                    // sends "Pushed to page 2 by the framed text." to page 2
                    // in Word's print; ours set it at the top of page 1.)
                    let xml = document.paragraphs[i].style.frameXML ?? ""
                    func number(_ key: String) -> Double? {
                        guard let r = xml.firstRange(of: key + "=\"") else { return nil }
                        return Double(xml[r.upperBound...].prefix { $0 != "\"" })
                    }
                    if xml.containsSubstring("w:wrap=\"notBeside\""), xml.containsSubstring("w:hRule=\"exact\""), let h = number("w:h"), h > 0 {
                        frameFoot = (target + _px(h / 20 + 2 * (number("w:vSpace") ?? 0) / 20), page, 0)
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
            if let tf = textFloatTop {
                textFloatTop = nil
                // (A paragraph with the strip beside a table at the right margin to itself stays level with
                // it as long as the table lasts: lo-717ff943's bullets, tdf97090.)
                let alongside = i > 0 && (tf.chained || _cells[i - 1]?.table == tf.table) && (besideChainEnd.map { tf.y + 0.01 < $0 } ?? false)
                    && _cells[i] == nil && _besideIndent(i, document.paragraphs[i], document)?.right == true
                if theme.wordRules, i > 0, tf.chained || _cells[i - 1]?.table == tf.table, _cells[i] == nil, tf.page == page,
                   !(_floatLeavesNoStrip(tf.table, i, document) && _floatFollowsFloat(tf.table, document)), frameReturn == nil, !_pageBreak[i], bottom - top <= tf.down + 0.01 || alongside {
                    frameReturn = (y, page)
                    y = tf.y
                    textFloatTop = (tf.table, page, tf.y + (bottom - top), tf.down - (bottom - top), true)
                }
                // (A paragraph too tall for what is left of the offset parts
                // there: the lines that fit stand over the table, the rest
                // under it. LibreOffice's tdf124675, tblpY 2340 twips under
                // three paragraphs of 100pt: the first line of the fourth
                // stands at 136.7 in Word's print, its second under the
                // table; ours set both under it.)
                else if theme.wordRules, RichTextTheme.wordWindowsPages, i > 0, tf.chained || _cells[i - 1]?.table == tf.table,
                        _cells[i] == nil, tf.page == page, frameReturn == nil, !_pageBreak[i], resumeCursor == nil,
                        tf.down > 0.01, bottom - top > tf.down + 0.01, document.paragraphs[i].image == nil,
                        // (A table with room beside it sets text there instead.)
                        let across = _columnWidths[tf.table]?.reduce(0, +), across >= _flowWidth(i) - _px(40),
                        _besideIndent(i, document.paragraphs[i], document) == nil,
                        // (Only where a line stands over the table and another goes under:
                        // all of its lines over it, and just its space after under, leaves
                        // it where it was.)
                        case let g = geometry(i), case let cs = Self._lineBottoms(g.painter).map({ g.textTop + $0 + (i < _firstLineLift.count ? _firstLineLift[i] : 0) }),
                        cs.count >= 2, cs[0] - top <= tf.down + 0.01 {
                    frameReturn = (y, page)
                    floatHold = (tf.y + tf.down, y)
                    y = tf.y
                }
                // (Held in by a header picture's strip, a line under a floating table is
                // stepped down from the anchor's line at its own pitch until it clears
                // the table, not set at its foot: Word's print of tdf38575 (lab bis)
                // has the blank after the anchor 269.2, the table's foot 261.3, in
                // slots of 13.8 from the anchor's 131.1; with the table cut to two
                // paragraphs 213.9 for a foot of 211.9.)
                else if theme.wordRules, RichTextTheme.wordWindowsPages, i > 0, tf.chained, _cells[i] == nil, tf.page == page, frameReturn == nil,
                        _setup(ofParagraph: i).headerWrapLeft > 0, bottom - top > 0.01, y > tf.y + 0.01 {
                    RuleTrace.hit("header-wrap-line-under-floating-table-steps")
                    let step = bottom - top
                    y = tf.y + (((y - tf.y) / step) - 0.001).rounded(.up) * step
                }
            }
            defer { floatHold = nil }
            defer {
                if let back = frameReturn, !(i + 1 < count && ownFrame != nil && document.paragraphs[i + 1].style.frameXML == ownFrame) {
                    if back.page == page { y = back.y }
                    frameReturn = nil
                }
            }
            // A paragraph that ends its section and holds only floating
            // objects takes no room (see `_layoutParagraph`), but stands on
            // its page all the same, its objects with it: zh-6d402586's
            // annexes are each a section of one such paragraph — a page's
            // picture and its "附件1" box — and Word draws them on the
            // annex's page; ours gave the paragraph no piece, and the page
            // stood blank.
            if theme.wordRules, bottom - top < 0.01, _cells[i] == nil, document.paragraphs[i].style.sectionXML != nil,
               (i < _floatImages.count && _floatImages[i] != nil) || (i < _inline.count && _inline[i].contains { $0.float != nil }) {
                add(PagePiece(paragraph: i, flowTop: top, flowBottom: top, page: page, pageY: y))
            }
            // (An empty mark of a continuous section that does not fit what
            // is left of the page takes none of it there, and opens no page:
            // zh-b8de3ae2's p9 ends in "資料來源：本所會計室" at 779 and the five
            // empty marks after it — the 4- and 2-column sections between —
            // stand nowhere in Word for Windows' print, p10 opening with
            // "表2". Where they fit they take their room, as under its
            // chart 10; see `_layoutParagraph`.)
            if RichTextTheme.wordWindowsPages, theme.wordRules, resumeCursor == nil, _cells[i] == nil,
               case let mark = document.paragraphs[i], mark.text.isEmpty, mark.image == nil, mark.style.sectionXML != nil,
               mark.style.sectionBreaksPage == false, bottom - cursor > contentH - y + 0.01 {
                add(PagePiece(paragraph: i, flowTop: top, flowBottom: top, page: page, pageY: y))
                cursor = bottom
            }
            while cursor < bottom - 0.01 {
                if leavesLead, pageFresh, y < 0.01, page > 0, cursor <= top + 0.01 { cursor = min(bottom, top + lead) }
                // (Space kept at a page's top is less the space after of
                // the paragraph that ended the page before: the two are
                // one gap to Word, and the part of it the last page left
                // behind is not set again. A heading of 18pt before under
                // `w:pageBreakBefore`, after Body Text's 6pt after, starts
                // 12pt down; 9pt before, 3; 6 or less, none — at 12, 16
                // and 20pt, labs `hd`..`hm`, 2026-10-14; without that
                // after, all of it.)
                else if theme.wordRules, !leavesLead, y < 0.01, page > 0, cursor <= top + 0.01, lead > 0.01,
                        i > 0, _cells[i - 1] == nil, !document.paragraphs[i].style.markFollowsBreak {
                    let prevAfter = _spacing(i - 1, document).after
                    if prevAfter > 0.01 { cursor = min(bottom, top + min(lead, prevAfter)) }
                }
                let available = (floatHold?.limit ?? contentH) - y
                let rest = bottom - cursor
                // (The last line may reach past the foot by its grid's
                // overhang.)
                // (A frame placed on the page stands where it is placed,
                // past the foot or not: zh-9db183d5's cover issuer, a 29.2pt
                // frame 751pt under a margin of -338 twips, ends 6.6pt under
                // the text's foot and stays on the cover in Word's print;
                // ours took it, and a page of its own, to page 2.)
                let placedFrame = theme.wordRules && ownFrame != nil && frameReturn?.page == page
                // (Not into the footnotes: over a page's notes the line ends
                // above them. zh-c15af02e's page 6, 45.7pt lines on a grid
                // over a one-line note, holds thirteen in Word's print; the
                // fourteenth reaches 4.3pt into the separator's line, and
                // its overhang let ours keep it.)
                let overhang = placedFrame ? .infinity : theme.wordRules && i < _overhang.count && pageNotes.isEmpty ? _overhang[i] : 0
                let lineOverhangs = !placedFrame && theme.wordRules && pageNotes.isEmpty && i < _lineOverhang.count ? _lineOverhang[i] : []
                // (The reach of line `k` past the foot: its own faces'.)
                func reach(_ k: Int) -> Double { k >= 0 && k < lineOverhangs.count ? max(overhang, lineOverhangs[k]) : overhang }
                // (A last line that is empty — only the paragraph mark, after a trailing line break —
                // is set though it hangs past the foot; any line with text must fit. Word for
                // Windows, lab lh3: lo-f5c618c5's 37-line paragraph, 36 line breaks, exact 13pt, keeps
                // its empty 37th line 0.75pt past the foot — and 1.85pt in a page 1pt shorter — on
                // page 1; with a letter on that line, or one more line after it, it goes on.)
                let emptyTail: Double = {
                    guard theme.wordRules, RichTextTheme.wordWindowsPages, document.paragraphs[i].cell == nil, let last = document.paragraphs[i].text.last,
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
                    let st = document.paragraphs[i].style
                    // (An "at least" line ties too in Word for Windows,
                    // where every line of the paragraph is its minimum:
                    // bug59058's page 28 ends in eight lines of
                    // at-least 15pt Times that fill the page to the twip,
                    // and Word for Windows keeps the eighth (word-win);
                    // Word for Mac takes it over, as ours did.)
                    guard let h = st.lineHeightPoints else { return false }
                    if st.lineHeightIsMinimum {
                        guard RichTextTheme.wordWindowsPages,
                              geometry(i).painter.computeLineMetrics().allSatisfy({ abs($0.height - _px(h)) < _px(0.01) }) else { return false }
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
                let pictureAfter: Double = theme.wordRules && RichTextTheme.wordWindowsPages && document.paragraphs[i].cell == nil
                    && (document.paragraphs[i].image != nil || _inlinePictureOnly(i, document)) ? _spacing(i, document).after : 0
                if rest - pictureAfter <= available + slack + reach(lineOverhangs.count - 1) + emptyTail {
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
                    if rest > available + 0.01, case let g = geometry(i), let line = Self._lineBottoms(g.painter).last {
                        let st = document.paragraphs[i].style
                        let offGrid = document.paragraphs[i].cell == nil && document.paragraphs[i].image == nil
                            && !(st.eastAsian["w:snapToGrid"] != "0" && _grid(i, document).pitch != nil)
                        let extra = theme.wordRules && offGrid && st.lineHeightPoints == nil
                            && st.lineSpacing - theme.lineSpacingReduction > 1.001 && i < _overhang.count ? _overhang[i] : 0
                        if g.textTop + line - extra - cursor > available + 0.01 { overfull = true } else { spacing = extra > 0 }
                    }
                    add(PagePiece(paragraph: i, flowTop: cursor, flowBottom: bottom,
                                                  page: page, pageY: y))
                    y += rest
                    if spacing || (pictureAfter > 0 && rest > available + 0.01) { spacedPast = y }
                    cursor = bottom
                    break
                }
                if cuts == nil {
                    let g = geometry(i)
                    let lift = i < _firstLineLift.count ? _firstLineLift[i] : 0
                    cuts = Self._lineBottoms(g.painter).map { g.textTop + $0 + lift }
                    if Self.debugPagination {
                        let m = g.painter.computeLineMetrics()
                        let desc = "para \(i) top \(g.top) textTop \(g.textTop) bottom \(g.bottom) painterH \(g.painter.height) lines \(m.count) heights \(m.map { $0.height }) baselines \(m.map { $0.baseline }) asc/desc \(m.first.map { "\($0.ascent)/\($0.descent)" } ?? "-") cursor \(cursor) y \(y) available \(available)\n"
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
                    ? document.paragraphs[i].style.borders?.bottom.map { _px($0.space + Self._ruleRoom($0.style, $0.width)) } ?? 0 : 0
                for (k, c) in cuts!.enumerated() where c > cursor + 0.01 && c - cursor <= available + slack + reach(k) + (k == cuts!.count - 1 ? emptyTail : -partFoot) { cut = c }
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
                if theme.wordRules, y > 0.01, document.paragraphs[i].image != nil || _inlinePictureOnly(i, document), cursor <= top + 0.01,
                   bottom - _spacing(i, document).after - cursor > available + slack + overhang { cut = nil }
                // (So does a paragraph of floating objects alone: its
                // painter's line is its anchors', under a point tall, where
                // the paragraph stands an empty line — cut there, the
                // sliver stayed at the foot as if the rest were its space
                // after, and its objects, drawn only with it whole, were
                // lost. zh-b24b396a's figure D2/D3, 36 groups anchored in
                // one paragraph that Word starts page 13 with, drew none.)
                if theme.wordRules, y > 0.01, cursor <= top + 0.01, _anchorsOnly(i, document),
                   bottom - _spacing(i, document).after - cursor > available + slack + overhang { cut = nil }
                // (Over a floating table's offset only a real part counts: where
                // just the paragraph's space after does not fit, the paragraph
                // goes under the table whole, as it did before it could part.)
                if floatHold != nil, let c = cut, let last = cuts!.last, c >= last - 0.01 { cut = nil }
                // Word's rules for where a paragraph may part: not at all
                // (`w:keepLines`), or — its widow and orphan control,
                // which is on unless the paragraph says otherwise — with
                // two lines at least on each side.
                // (At a page's top too, for its widow control alone: a paragraph that
                // fills a page and leaves one line for the next gives that page
                // a line to keep company: tdf136952's p2, 17 lines, ends with
                // two on p3 in Word's print, where ours left one.)
                let atTop = !(y > 0.01 || cursor > top + 0.01)
                if theme.wordRules, floatHold == nil, let chosen = cut {
                    let st = document.paragraphs[i].style
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
                    } else if st.keepLines, bottom - top <= contentH + 0.01 {
                        if last < all.count - 1 { keep = 0 }
                    } else if st.widowControl, !document.widowControlSuspended,
                              // (A wrapper table's text is a cell's, set as the body is: before
                              // Word's 2013 layout a cell keeps no widow or orphan —
                              // floattable-del-empty's last paragraph of page 5, two lines,
                              // parts after its first in Word's print.)
                              !(RichTextTheme.wordWindowsPages && (document.compatibilityMode ?? 12) < 15
                                && document.paragraphs[i].keptTable?.hasPrefix("kc") == true) {
                        if all.count - 1 - last == 1 { keep -= 1 }
                        // (An orphan only where lines go on: the whole of
                        // a one-line paragraph fits, though its space
                        // after does not — bug59058's thirteenth empty
                        // paragraph under a table, 15.4pt of line in
                        // 17.3pt left, stays at the foot in Word. Not a
                        // picture's paragraph, whose cuts are its empty
                        // line's and not the picture's: bug57031's 360pt
                        // chart then started at page 1's foot.)
                        if cursor <= top + 0.01, keep < 2, last < all.count - 1 || document.paragraphs[i].image != nil { keep = 0 }
                    }
                    // (Nor does a page end with a line its automatic hyphenation parted a word at, in Word for
                    // Windows: lab `pf` (lo-000463df's styles, an 8-line paragraph whose lines 2 and 5 end "…ti-")
                    // never leaves 2 or 5 of its lines at the foot, at any spacing or space before — one fewer, and
                    // under widow control none for 2; with line breaks there instead, 5 stay. lo-000463df's
                    // paragraph 37 so: none of it on page 2 in Word's print, one with widow control off.)
                    if RichTextTheme.wordWindowsPages, keep > 0, first + keep < all.count, let shown = _hyphenShown[i], !shown.isEmpty,
                       let g = Optional(geometry(i)), i < _inserts.count {
                        let starts = _lineStarts(g.painter, _OffsetMap(lead: _lead(i), inserts: _inserts[i]), count: document.paragraphs[i].text.utf16.count)
                        let next = first + keep
                        if next < starts.count, shown.contains(starts[next]), _hyphenPoints[i]?.contains(starts[next]) == true {
                            keep -= 1
                            if st.widowControl, !document.widowControlSuspended, !atTop, keep < 2 { keep = 0 }
                        }
                    }
                    if keep <= 0 {
                        // (Only where a new page gives it more room.)
                        if y > 0.01 { cut = nil }
                    } else {
                        cut = all[first + keep - 1]
                    }
                }
                // (A picture's line taller than the page, at a page's top: its
                // cut is the grid's pitch under the picture's top, and the page
                // took that sliver; Word keeps the picture whole, over the foot.)
                if theme.wordRules, cut != nil, y <= 0.01, cursor <= top + 0.01, (document.paragraphs[i].image != nil || _inlinePictureOnly(i, document)),
                   bottom - _spacing(i, document).after - cursor > available + slack + overhang {
                    add(PagePiece(paragraph: i, flowTop: cursor, flowBottom: bottom, page: page, pageY: y))
                    cursor = bottom
                    y = contentH
                    break
                }
                if let cut {
                    if cut - cursor > available + 0.01 { overfull = true }
                    add(PagePiece(paragraph: i, flowTop: cursor, flowBottom: cut,
                                                  page: page, pageY: y))
                    cursor = cut
                    // (Where the cut is under the paragraph's last line,
                    // what is left is its space after: Word leaves that at
                    // the page's foot, and the next page starts with the
                    // next paragraph — carried over, it set zh-a4b0f6ea's
                    // page 8 heading 8pt low.)
                    if theme.wordRules, let lastLine = cuts!.last, cut >= lastLine - 0.01 {
                        cursor = bottom
                        y = contentH
                        break
                    }
                    if let hold = floatHold { y = hold.back; floatHold = nil; frameReturn = nil } else { newPage() }
                } else if floatHold != nil {
                    // Nothing fits over the table: all of it goes under.
                    y = floatHold!.back; floatHold = nil; frameReturn = nil
                } else if y > 0.01, theme.wordRules, RichTextTheme.wordWindowsPages, document.paragraphs[i].text.isEmpty,
                          document.paragraphs[i].image == nil, i + 1 < count, document.paragraphs[i + 1].style.markFollowsBreak,
                          _pageBreak[i + 1], bottom - cursor <= contentH - y + _px(2.5) {
                    // (A line that holds only a page break, hung a little past the foot
                    // (the length of a line's leading), stays on its page and the break
                    // ends it: lo floattable-header's 13.8pt line at 761.6, the foot at
                    // 788.2, is page 1's last in Word's print; ours took it to a page
                    // of its own and the table after it to the page after, 10 pages
                    // for 8.)
                    RuleTrace.hit("page-break-line-hangs-past-the-foot")
                    add(PagePiece(paragraph: i, flowTop: cursor, flowBottom: bottom, page: page, pageY: y))
                    cursor = bottom
                    y = contentH
                    break
                } else if y > 0.01 {
                    // Nothing fits in what is left of this page: start a new one.
                    newPage()
                } else {
                    // A single line taller than a page: place it and overflow.
                    // (A picture's paragraph whole, the line under the picture
                    // too: zh-6d402586's "參考資料1", a 749pt picture on a page
                    // of 698, is page 26 in Word's print, its mark and section
                    // break with it, and "參考資料2" page 27; ours carried the
                    // 9pt under the picture to a page 27 of its own, and the
                    // next section went to 28.)
                    let pictureOnly = document.paragraphs[i].image != nil || _inlinePictureOnly(i, document)
                    let next = theme.wordRules && pictureOnly ? bottom
                        : cuts!.first(where: { $0 > cursor + 0.01 }) ?? bottom
                    add(PagePiece(paragraph: i, flowTop: cursor, flowBottom: next,
                                                  page: page, pageY: y))
                    cursor = next
                    if theme.wordRules, pictureOnly {
                        // (The page is full; what follows opens the next one.)
                        y = contentH
                        break
                    }
                    newPage()
                }
            }
        }
        if !deferredUnder.isEmpty { placeDeferred() }
        if notesOn {
            // (Notes still waiting at the end — every paragraph kept to
            // the last — stand at the last page's foot.)
            if !pendingNotes.isEmpty { reserveNotes(pendingNotes); pendingNotes = [] }
            if !rowPending.isEmpty { reserveNotes(rowPending); rowPending = [] }
            _pageNotes[page] = pageNotes
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
        if theme.wordRules, RichTextTheme.wordWindowsPages, _columns > 1, !document.footnotes.isEmpty, !slotNotes {
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
                            let o = origin[piece.paragraph] ?? 0
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
                           left: same ? _pxColumnLeft(phys, column: 0, paragraph: first) : _pxMarginLeft(phys), perColumn: same)
                _columnNoteGeometry[phys] = geo
                // (Each column's room is its own notes' and the rule over them:
                // Word's lab fn-cols-long2 and -short, the notes standing
                // under the column their marks stand in.)
                if same, let lay = _columnNoteLayout(phys, ids, document) {
                    for (c, h) in lay.colHeights.enumerated() where h > 0 { needed[phys * _columns + c] = h + lay.separator }
                }
            }
            // (Shortening a column moves marks, and with them notes, to
            // other columns, so the rooms can chase each other; from the
            // third round they only grow, which settles.)
            let raw = needed
            if _columnNoteRounds >= 2 { for (k, v) in _columnNoteRaw { needed[k] = max(needed[k] ?? 0, v) } }
            _columnNoteRaw = raw
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
        case "thinThickSmallGap", "thickThinSmallGap": return width + 1.5
        case "thinThickMediumGap", "thickThinMediumGap": return width * 2
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
        case "thinThickSmallGap", "thinThickMediumGap", "thinThickLargeGap": return [(0, width), (width + gap, thin)]
        case "thickThinSmallGap", "thickThinMediumGap", "thickThinLargeGap": return [(0, thin), (thin + gap, width)]
        default: return [(0, width)]
        }
    }

    public var isPaged: Bool { pageSetup != nil }
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
            return a.table == b.table && b.row > a.row
        }
        let skipAfter = contextual && (sameStyle(i + 1) || nextRow(i + 1)) && !keepsLines(i + 1, "w:afterLines")
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
        if theme.wordRules, web {
            if i == 0 {
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
        return ((skipBefore ? 0 : _px(spaceBefore * k)) + _px(divTop),
                (skipAfter || dropAfter ? 0 : _px(spaceAfter(i) * k)) + _px(divBottom))
    }

    /// The sheet's Normal look, for `RichTextTheme.textStyle`.
    func _normalChar(_ document: RichDocument) -> CharStyle? { document.styles[RichNamedStyle.normalId]?.char }

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
