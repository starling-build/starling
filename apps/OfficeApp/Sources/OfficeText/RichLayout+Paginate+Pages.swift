// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paginate+Pages": steps of `_paginate`, once nested functions of it (a pure move: the variables
// they shared are `_PState`, passed inout).

import Flutter
import FlutterSwiftBridge
import Foundation

extension RichLayout {
    func _pg_openPage(_ pgs: inout _PState, _ document: RichDocument) {
        pgs.pageFresh = true
        let para = min(pgs.i, max(0, count - 1))
        let physical = pgs.page / _columns
        if pgs.page % _columns == 0 {
            while _pageSection.count <= physical { _pageSection.append(0) }
            _pageSection[physical] = para < _sectionOf.count ? _sectionOf[para] : max(0, _sectionSetups.count - 1)
            _pageHeaderSection[physical] = nil
            // (A page that opens on the empty mark closing a continuous
            // section belongs to the section after it: lo
            // 090716_Studentische_Arbeit_VWS' page 3 opens on such a mark
            // of the second section, whose default header has text, and
            // Word's print gives the page the third section's empty one.)
            if theme.wordRules, physical > 0, pgs.i > 0, pgs.i < count, pgs.i + 1 < _sectionOf.count, pgs.i < _cells.count, _cells[pgs.i] == nil,
               case let mark = document.paragraphs[pgs.i], mark.text.isEmpty, mark.image == nil, mark.style.sectionXML != nil,
               mark.style.sectionBreaksPage == false, _sectionOf[pgs.i + 1] != _sectionOf[pgs.i] {
                RuleTrace.hit("page-opens-on-a-continuous-section-mark")
                _pageHeaderSection[physical] = _sectionOf[pgs.i + 1]
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
        if theme.wordRules, pgs.page > 0, para < count, case let st = document.paragraphs[para].style,
           st.frameInsetTop > 0 || st.frameInsetBottom > 0,
           _pages[pgs.page - 1].contains(where: { $0.paragraph < count && !$0.repeated && document.paragraphs[$0.paragraph].style.frameInsetTop + document.paragraphs[$0.paragraph].style.frameInsetBottom > 0 }) {
            insets.top += _px(st.frameInsetTop)
            insets.bottom += _px(st.frameInsetBottom)
        }
        while _pageInsetTop.count <= physical { _pageInsetTop.append(0) }
        _pageInsetTop[physical] = insets.top
        pgs.contentH = max(1, _px(pageSetup(forPage: physical).height) - insets.top - insets.bottom - (_columns > 1 ? _columnNoteReserve[pgs.page] ?? 0 : 0))
    }

    // (A header picture that starts under the header's last line leaves the body's start alone, but the body's lines keep clear
    // of it: the first whose box touches it stands at its foot. Word's prints of sa2 0840cb25's lab, rule 13.8 to 40pt under a 12.6pt line.)
    func _pg_addHeaderBand(_ pgs: inout _PState, _ document: RichDocument) {
        guard theme.wordRules, RichTextTheme.wordWindowsPages else { return }
        let physical = pgs.page / _columns
        guard let header = _headerFooter(.header, page: physical, document, pageCount: 1),
              let band = _headerBandUnderLastLine(header, pageSetup(forPage: physical)) else { return }
        // (A page that holds a figure of its own that the text goes over and under, set from its paragraph: Word's prints of
        // the lab hdrfig (h0, m15 to m40, 7 prints within 0.05 pt) charge the push D (the rule's foot less the box top of the first
        // line it touches) at the FIGURE when D reaches the gap between the anchor paragraph's line foot and the figure's top:
        // the text above and the anchor line stay, the figure and all after it go down by D. Under the gap D lands at the
        // page's top, as for a page without a figure. The first figure on the page decides; amd-opus's rule B, board 173311.)
        let first = min(pgs.i, max(0, count - 1))
        let top = _bodyInsets(page: physical, document).top
        for k in first..<min(count, first + 60) {
            guard _cells[k] == nil else { continue }
            let own = ((k < _floatImages.count ? [_floatImages[k]].compactMap { $0 } : []) + (k < _inline.count ? _inline[k] : []))
            guard own.contains(where: { $0.float.map { ($0.takesRoom || $0.bandsPage) && !$0.wraps && $0.verticalFrom == "paragraph" } ?? false }) else { continue }
            guard let figure = own.first(where: { $0.float.map { ($0.takesRoom || $0.bandsPage) && !$0.wraps && $0.verticalFrom == "paragraph" } ?? false }),
                  let f = figure.float, f.verticalAlign == nil, k < _painters.count, _painters[k] != nil, first < _painters.count, _painters[first] != nil,
                  _cells[first] == nil else { break }
            // The first line the rule touches, over the lines of the paragraphs from the page's start on.
            let bandTop = band.top - top, bandBottom = band.bottom - top
            var cum = 0.0
            var d: Double? = nil
            scan: for p in first..<min(count, first + 12) {
                guard _cells[p] == nil, p < _painters.count, p < _heights.count, _painters[p] != nil else { break }
                var lineTop = cum
                for foot in Self._lineBottoms(geometry(p).painter) {
                    if cum + foot > bandTop + 0.01 { d = bandBottom - lineTop; break scan }
                    lineTop = cum + foot
                }
                cum += _heights[p]
            }
            guard let push = d, push > 0.01 else { break }
            let anchorFoot = Self._lineBottoms(geometry(k).painter).first ?? 0
            let gap = _px(f.y) - anchorFoot
            if push >= gap {
                RuleTrace.hit("word-header-picture-push-is-charged-at-the-top-and-bottom-figure")
                // From the document's own float, so a pass that opens the page again does not add it twice.
                func moved(_ image: ImageAttachment) -> ImageAttachment {
                    var out = image
                    if var g = out.float, let orig = document.paragraphs[k].image?.float ?? document.paragraphs[k].inlineImages.values.first(where: { $0.id == image.id })?.float { g.y = orig.y + push / _px(1); out.float = g }
                    return out
                }
                if k < _floatImages.count, let image = _floatImages[k] { _floatImages[k] = moved(image); _floats[k] = _floatImages[k]?.float }
                if k < _inline.count { _inline[k] = _inline[k].map { $0.float == nil ? $0 : moved($0) } }
                return
            }
            break
        }
        RuleTrace.hit("word-header-picture-below-the-last-line-keeps-the-body-lines-clear")
        pgs.fixedBands.append((band.top - top, band.bottom - top, 0, 1e9))
    }

    func _pg_loadPins(_ pgs: inout _PState, _ document: RichDocument) {
        pgs.pinBands = _pinnedFloats.values.filter { $0.page == pgs.page }.map { ($0.top, $0.bottom, $0.left, $0.right) }
        pgs.bands += pgs.pinBands
    }

    // Down past the pinned floats that what is `height` tall would
    // run into here.
    func _pg_underPins(_ pgs: inout _PState, _ document: RichDocument, _ height: Double) {
        var steps = 0
        while steps < 4, let b = pgs.pinBands.first(where: { $0.top < pgs.y + height - 0.5 && $0.bottom > pgs.y + 0.5 }) {
            pgs.y = b.bottom
            steps += 1
        }
    }

    func _pg_noteWidth(_ pgs: inout _PState, _ document: RichDocument) -> Double {
        let s = pageSetup(forPage: pgs.page / _columns)
        return _px(pgs.slotNotes ? s.columnWidth : s.contentWidth)
    }

    func _pg_reserveNotes(_ pgs: inout _PState, _ document: RichDocument, _ ids: [Int], deferring: Bool = false) {
        guard pgs.notesOn else { return }
        let width = _pg_noteWidth(&pgs, document)
        var deferred = false
        for id in ids where !pgs.pageNotes.contains(id) {
            if deferred { if !pgs.pendingNotes.contains(id) { pgs.pendingNotes.append(id) }; continue }
            guard let note = _note(id, width: width, document) else { continue }
            var room = pgs.pageCut?.id == id ? pgs.pageCut!.keep : note.height
            if pgs.pageNotes.isEmpty { room += _note(-1, width: width, document)?.height ?? 0 }
            if deferring, room > pgs.contentH - pgs.y + 0.01 {
                deferred = true
                if !pgs.pendingNotes.contains(id) { pgs.pendingNotes.append(id) }
                continue
            }
            pgs.contentH = max(1, pgs.contentH - room)
            pgs.pageNotes.append(id)
        }
    }

    func _pg_newPage(_ pgs: inout _PState, _ document: RichDocument) {
        pgs.bands.removeAll()
        pgs.fixedBands.removeAll()
        pgs.tightBandBottoms.removeAll()
        pgs.tableBands.removeAll()
        pgs.pictureBands.removeAll()
        pgs.narrowBands.removeAll()
        pgs.anchorRun.removeAll()
        pgs.markOnPage = false
        pgs.overfull = false
        pgs.spacedPast = nil
        var carried: [Int] = []
        var goesOn: Double? = nil   // where the paragraph parted here goes on, in its flow
        if pgs.notesOn {
            let stays = _pages[pgs.page].contains { pgs.placingRange.contains($0.paragraph) && !$0.repeated }
            carried = stays ? [] : pgs.placing.filter { pgs.pageNotes.contains($0) }
            if !stays { carried += pgs.rowPending; pgs.rowPending = [] }
            // (A paragraph parted here keeps on this page only the
            // notes whose marks are in its lines here: zh-424775e4's
            // footnote 2, marked in the fourth line of a paragraph
            // that page 9 holds the first three of, stands at page
            // 10's foot in Word's print; ours set it on page 9, and
            // took three more lines over for it.)
            if stays, theme.wordRules, pgs.placingRange.count == 1, _cells[pgs.placingRange.lowerBound] == nil,
               let here = _pages[pgs.page].last(where: { $0.paragraph == pgs.placingRange.lowerBound && !$0.repeated }) {
                carried = pgs.placing.filter { id in
                    pgs.pageNotes.contains(id) && (_footnoteMarkTop(pgs.placingRange.lowerBound, id, document).map { $0 >= here.flowBottom - 0.01 } ?? false)
                }
                goesOn = here.flowBottom
            }
            // (A paragraph that begins on this new page, none of it on the
            // last, takes the notes its marks call for as one going on
            // does: only those whose marks stand in the lines this page
            // will hold. f69b0ddd's paragraph "E hoje dá-se o mesmo?",
            // begun at page 3's head, marks notes 4 and 5 in its 6th and
            // 15th lines; Word sets both at page 3's foot with 17 lines,
            // ours reserved all three at once and ran 12.)
            if !stays, theme.wordRules, pgs.placingRange.count == 1, _cells[pgs.placingRange.lowerBound] == nil, !pgs.placing.isEmpty {
                goesOn = _tops[pgs.placingRange.lowerBound]
            }
            _pageNotes[pgs.page] = pgs.pageNotes.filter { !carried.contains($0) }
            if let cut = pgs.pageCut, _pageNotes[pgs.page]?.contains(cut.id) == true { _noteCutOut[pgs.page] = cut } else { pgs.pageCut = nil }
            pgs.pageNotes = []
            // (The notes still waiting for an unkept paragraph go
            // over too, after those carried, in the file's order.)
            for id in pgs.pendingNotes where !carried.contains(id) { carried.append(id) }
            pgs.pendingNotes = []
            carried.sort()
        }
        var fresh: [PagePiece] = []
        fresh.reserveCapacity(32)
        if pgs.page + 1 < _pages.count { pgs.page += 1 } else { _pages.append(fresh); pgs.page += 1 }
        // (A section of fewer columns than the most has none past its
        // last: the next page's first.)
        if _perSection, case let here = _columnsOf(paragraph: min(pgs.i, max(0, count - 1))), here < _columns {
            while pgs.page % _columns >= here {
                if pgs.page + 1 < _pages.count { pgs.page += 1 } else { _pages.append([]); pgs.page += 1 }
            }
        }
        pgs.prevY = pgs.y
        pgs.y = 0
        // (Where the flowed endnotes go on from the page before, Word sets the continuation separator's line
        // first: xb por-z1326468's pages 27 and 28 start 13 pt lower.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.i < count, document.paragraphs[pgs.i].flowedEndnote.map({ $0 >= 0 }) == true,
           pgs.page > 0, _pages[pgs.page - 1].contains(where: { document.paragraphs[$0.paragraph].flowedEndnote != nil }),
           !document.endnoteContinuation.isEmpty,
           let rule = document.paragraphs.firstIndex(where: { $0.flowedEndnote == -1 }) {
            pgs.y = _markLineHeight(rule, document, single: true, paragraph: document.endnoteContinuation[0])
        }
        // (A column of a page whose columns were balanced at a
        // continuous break starts under the balanced block.)
        if let floor = pgs.columnFloor, floor.physical == pgs.page / max(1, _columns) { pgs.y = floor.y }
        pgs.prevContentH = pgs.contentH
        _pg_openPage(&pgs, document)
        _pg_addHeaderBand(&pgs, document)
        _pg_loadPins(&pgs, document)
        // (The rest of a note the page before parted, first under the
        // rule.)
        if pgs.notesOn, let cut = pgs.pageCut {
            pgs.pageCut = nil
            let width = _pg_noteWidth(&pgs, document)
            if let note = _note(cut.id, width: width, document) {
                pgs.contentH = max(1, pgs.contentH - (note.height - cut.keep) - (_note(-1, width: width, document)?.height ?? 0))
                pgs.pageNotes.append(cut.id)
                _noteCarryIn[pgs.page] = (cut.id, cut.keep)
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
        if pgs.notesOn, theme.wordRules, let flow = goesOn {
            let i0 = pgs.placingRange.lowerBound
            let mine = (carried + pgs.rowPending).filter { pgs.placing.contains($0) }.sorted()
            carried.removeAll { mine.contains($0) }
            pgs.rowPending = []
            _pg_reserveNotes(&pgs, document, carried)
            let width = _pg_noteWidth(&pgs, document)
            var here: [Int] = []
            var room = 0.0
            for (n, id) in mine.enumerated() {
                guard let mark = _footnoteMarkLine(i0, id, document), let note = _note(id, width: width, document) else { here.append(id); continue }
                room += note.height + (pgs.pageNotes.isEmpty && here.isEmpty ? _note(-1, width: width, document)?.height ?? 0 : 0)
                let at = pgs.y + (mark.bottom - flow)
                if at + room > pgs.contentH + 0.01 {
                    let left = pgs.contentH - at - (room - note.height)
                    if pgs.pageCut == nil, let keep = _noteCuts(id, width: width, document).last(where: { $0 <= left + 0.01 }) {
                        pgs.pageCut = (id, keep)
                        here.append(id)
                        pgs.rowPending = Array(mine[(n + 1)...])
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
                        if pgs.y > 0.01 || mark.top - flow > 0.5 {
                            pgs.contentH = max(1, min(pgs.contentH, pgs.y + (mark.top - flow) + (here.isEmpty ? 0 : room - note.height)))
                        }
                        pgs.rowPending = Array(mine[n...])
                    }
                    break
                }
                here.append(id)
            }
            _pg_reserveNotes(&pgs, document, here)
            return
        }
        _pg_reserveNotes(&pgs, document, carried)
    }

    func _pg_add(_ pgs: inout _PState, _ document: RichDocument, _ piece: PagePiece) {
        _pages[pgs.page].append(piece)
        _allPieces.append(piece)
        pgs.pageFresh = false
    }

    // A table's header row, repeated at the top of each later page it
    // runs on: the row's pieces again, marked, in the page only.
    // How many of a table's first rows are its header, repeated on
    // each page it runs on: the rows the file marks — none where it
    // marks them all, which Word repeats nothing of (a form of
    // sixteen rows, each marked: every page began with the form's
    // head again and never got past it).
    func _pg_headerRows(_ pgs: inout _PState, _ document: RichDocument, _ table: String) -> Int {
        guard let ts = document.tableStyles[table], ts.headerRow else { return 0 }
        let n = theme.wordRules ? max(1, ts.headerRowCount) : 1
        return theme.wordRules && n > (_tableRows[table] ?? 0) ? 0 : n
    }

    func _pg_repeatHeader(_ pgs: inout _PState, _ document: RichDocument, of table: String, before i: Int) {
        // (Nothing where the page breaks inside the header: its rows
        // go on as rows. bug57031's "Test of Equality over Strata",
        // two header rows parted after the first at page 12's foot,
        // opens page 13 with its second once in Word's print, where
        // ours set both again above it: the second twice.)
        if theme.wordRules, let r = _cells[i]?.row, _cells[i]?.table == table, r < _pg_headerRows(&pgs, document, table) { return }
        var k0 = i
        while k0 > 0, let d = _cells[k0 - 1], d.table == table { k0 -= 1 }
        guard let h = _cells[k0], h.row == 0 else { return }
        // (Nor where the header and the row under it that may not part do
        // not stand on a page together: lo Cool16066_addRowsUnderOmittedHeading's
        // 10 cm header and its 40-line row, whole, make 843pt for 728, and
        // Word's print sets the row at page 2's top with no header over it.)
        if theme.wordRules, let next = _cells[i], next.table == table, next.row >= _pg_headerRows(&pgs, document, table),
           document.tableStyles[table]?.rowsCantSplit.contains(next.row) == true {
            var head = 0.0
            var n = k0
            while n < count, let d = _cells[n], d.table == table, d.row < _pg_headerRows(&pgs, document, table) {
                head = max(head, d.rowTop + d.ownRowHeight - h.rowTop)
                n += 1
            }
            if head + next.ownRowHeight > pgs.contentH + 0.01, next.ownRowHeight <= pgs.contentH + 0.01 {
                pgs.omittedHeadHeight[table] = head
                return
            }
        }
        // (Every row the file marks as a header, where Word's rules
        // are followed: a heading of two rows is repeated whole.)
        let rows = _pg_headerRows(&pgs, document, table)
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
                let pageY = pgs.y + (d.rowTop - h.rowTop)
                for k in n ... last {
                    var piece = PagePiece(paragraph: k, flowTop: d.rowTop + up, flowBottom: d.rowTop + up + cut, page: pgs.page, pageY: pageY)
                    piece.repeated = true
                    piece.part = .text
                    pieces.append(piece)
                }
                var rules = PagePiece(paragraph: n, flowTop: d.rowTop, flowBottom: d.rowTop + cut, page: pgs.page, pageY: pageY)
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
            var piece = PagePiece(paragraph: j, flowTop: d.rowTop, flowBottom: bottom, page: pgs.page, pageY: pgs.y + (d.rowTop - h.rowTop))
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
        guard height < pgs.contentH - pgs.y - 1 else { return }
        _pages[pgs.page].append(contentsOf: pieces)
        pgs.y += height
    }
}
