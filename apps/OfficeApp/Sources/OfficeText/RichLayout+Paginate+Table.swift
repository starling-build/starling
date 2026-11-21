// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paginate+Table": steps of `_paginate`, once nested functions of it (a pure move: the variables
// they shared are `_PState`, passed inout).

import Flutter
import FlutterSwiftBridge
import Foundation

extension RichLayout {
        // (A table that asks for the body's foot, `w:tblpYSpec="bottom"`:
        // its foot at the body's, as its offset from the page's top.
        // LibreOffice's floattable-from-bottom has it 621pt down a 792pt
        // page in Word's print, margin at 720; ours stood it at the top.)
    func _pg_bottomAlignedOffset(_ pgs: inout _PState, _ document: RichDocument, _ c: _CellGeo, _ i: Int) -> Double? {
            guard theme.wordRules, document.tableStyles[c.table]?.bottomAligned == true else { return nil }
            var bottom = c.rowTop + c.ownRowHeight, k = pgs.i
            while k < count, let d = _cells[k], d.table == c.table { bottom = max(bottom, d.rowTop + d.ownRowHeight); k += 1 }
            let height = bottom - c.rowTop
            guard height < pgs.contentH else { return nil }
            let physical = pgs.page / _columns
            let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
            // (A hair short of the foot: a table that ends on it opens a page.)
            return (pgs.contentH - height - 0.5 + insetTop) / _px(1)
        }

    func _pg_raiseAtHead(_ pgs: inout _PState, _ document: RichDocument, _ c: _CellGeo) {
            // (At the head too under nothing but what takes no room in
            // Word's flow: frames, and tables floating by the text.
            // zh-76700e5f's ICS/CCS table comes after the cover's
            // floating "3311" table and two frames, and stands at
            // 34.5 in Word's print; ours set it under the "3311"
            // table, at 177.7.)
            let floatsOnly = !_pages[pgs.page].isEmpty && _pages[pgs.page].allSatisfy { piece in
                let q = document.paragraphs[piece.paragraph]
                if let d = _cells[piece.paragraph] { return d.table != c.table && document.tableStyles[d.table]?.floatsOverText == true }
                return q.style.frameXML != nil
            }
            guard theme.wordRules, c.row == 0, c.firstInRow, pgs.i == 0 || _cells[pgs.i - 1]?.table != c.table,
                  let up = document.tableStyles[c.table]?.floatRaiseY, pgs.y < 0.01 || floatsOnly else { return }
            let physical = pgs.page / _columns
            let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
            pgs.y = max(-insetTop, -_px(up))
        }

        // (A table floating by the text that opens a page and has more rows than the body holds is
        // lifted, not parted where the body ends: Word sets as many of its whole rows as the page, from
        // its top edge, holds so that the last ends at the body's foot, the top of the first over the
        // margin. LibreOffice's floattable-footer-object, 55pt rows, a body 209pt high under a footer
        // picture: five rows a page, the first at 6.2pt down a page, the fifth ending at the foot.)
    func _pg_liftToFoot(_ pgs: inout _PState, _ document: RichDocument, _ c: _CellGeo) {
            guard theme.wordRules, RichTextTheme.wordWindowsPages, c.firstInRow, _pages[pgs.page].isEmpty,
                  let ts = document.tableStyles[c.table], ts.floatsOverText, !ts.pageAnchored, pgs.y < _px(1) + 0.01 else { return }
            let physical = pgs.page / _columns
            guard let footer = _headerFooter(.footer, page: physical, document, pageCount: 1),
                  _footerPictureEnd(footer, pageSetup(forPage: physical)) != nil else { return }
            let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
            var heights: [Double] = [], seen = Set<Int>(), k = pgs.i
            while k < count, let d = _cells[k], d.table == c.table {
                if d.row >= c.row, seen.insert(d.row).inserted { heights.append(d.ownRowHeight) }
                k += 1
            }
            let all = heights.reduce(0, +)
            guard all > pgs.contentH - pgs.y + 0.01 else { return }
            var run = 0.0, n = 0
            for h in heights { if run + h <= pgs.contentH + insetTop + 0.01 { run += h; n += 1 } else { break } }
            guard n >= 2, run > pgs.contentH - pgs.y + 0.01 else { return }
            RuleTrace.hit("floating-table-lifted-to-end-at-the-foot")
            pgs.y = pgs.contentH - run - _pg_ruleUnder(&pgs, document, c)
        }

    func _pg_tableRow(_ pgs: inout _PState, _ document: RichDocument, _ c: _CellGeo, _ sectionBreakHandled: Bool) {
        // (Where the row opens the page, a break it states is no
        // break, whatever offset the table is then set down by:
        // LibreOffice's tdf115883, a table placed 0.05pt under its
        // page's margin with w:pageBreakBefore in its first cell,
        // is the document's first page in Word's print; ours began
        // with a blank one.)
        let rowOpensThePage = pgs.y < 0.01 && _pages[pgs.page].isEmpty && !(theme.wordRules && pgs.markOnPage)
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
           c.row == 0, c.firstInRow, pgs.i == 0 || _cells[pgs.i - 1]?.table != c.table, pgs.y > 0.01,
           let ts = document.tableStyles[c.table], ts.headerRow, ts.headerRowCount > (_tableRows[c.table] ?? 0),
           document.tableStyles[c.table]?.floatX == nil {
            var last = pgs.i
            while last + 1 < count, _cells[last + 1]?.table == c.table { last += 1 }
            if last < _tops.count, _tops[last] + _heights[last] - _tops[pgs.i] > pgs.contentH - pgs.y { _pg_newPage(&pgs, document) }
        }
        // (So does one whose header rows, the ones marked, are
        // taller together than a page, which nothing could part:
        // tdf88496's eight, 702.5pt on a 700.2pt page, after a
        // paragraph at the head of page 1, open page 2 in Word's
        // print, the paragraph alone on 1; ours stood the table
        // under it and ran a page long.)
        if theme.wordRules, (document.compatibilityMode ?? 12) >= 15,
           c.row == 0, c.firstInRow, pgs.i == 0 || _cells[pgs.i - 1]?.table != c.table, pgs.y > 0.01,
           let ts = document.tableStyles[c.table], ts.headerRow, ts.headerRowCount > 0,
           ts.headerRowCount <= (_tableRows[c.table] ?? 0), ts.floatX == nil {
            var last = pgs.i
            while last + 1 < count, let d = _cells[last + 1], d.table == c.table, d.row < ts.headerRowCount { last += 1 }
            // (The rows' own heights: a row's cells are paragraphs whose
            // text may be short of it.)
            var bottom = 0.0
            for k in pgs.i ... last { if let d = _cells[k] { bottom = max(bottom, d.rowTop + d.rowHeight) } }
            let block = bottom - c.rowTop
            if block > pgs.contentH - pgs.y { RuleTrace.hit("header-block-over-rest") }
            if block > pgs.contentH + 0.01 {
                RuleTrace.hit("header-block-over-page")
                _pg_newPage(&pgs, document)
            }
        }
        // A table floating by the text straight after another that does,
        // at an offset no higher than the first's, avoids it: it stands
        // 21.5pt lower than the first's foot puts it — lab fs1 (Word for
        // Windows, LibreOffice's floattable-tables-lost): Outer table 2 is
        // 115.34pt under Table 1's text with Table 1's row 91.5pt, 73.82
        // with 50, 30.48 more with a second row of 30; ours 92.5 (the
        // constant is one witness's, not a distance the file states).
        if theme.wordRules, RichTextTheme.wordWindowsPages, c.row == 0, c.firstInRow, pgs.i > 0, let before = _cells[pgs.i - 1],
           before.table != c.table, let first = document.tableStyles[before.table], first.floatsOverText, !first.pageAnchored,
           let second = document.tableStyles[c.table], second.floatsOverText, !second.pageAnchored {
            let firstAt: Double = (first.floatOffsetY ?? 0) - (first.floatRaiseY ?? 0)
            let secondAt: Double = (second.floatOffsetY ?? 0) - (second.floatRaiseY ?? 0)
            // (Labs flt2 and ovl2 autow: the step is taken only when BOTH tables
            // are auto-width. Two tables that state a width sit level (flt2), and
            // so does an auto-width second one after a first that states its width:
            // T10 to T11 is 172pt in Word's print, ours 192 with the step.)
            if secondAt >= firstAt, second.width == nil, second.widthPercent == nil, first.width == nil, first.widthPercent == nil { pgs.y += _px(21.5) }
        }
        // (A table floating by the text straight after another that does, standing wholly beside it
        // (its box clear of the first's at the side), where the first runs over from an earlier page:
        // it starts level with the first's rows on this page, at their top, not under the first's foot.
        // Word's print of dx2 33a4668e, 16 two-page floating tables, left and right in turn: each
        // starts on the page the one before it ends on, level with its continuation; ours set it at
        // the next page, under the spill of the first.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, c.row == 0, c.firstInRow, pgs.i > 0, let before = _cells[pgs.i - 1],
           before.table != c.table, let first = document.tableStyles[before.table], first.floatsOverText, !first.pageAnchored,
           let second = document.tableStyles[c.table], second.floatsOverText, !second.pageAnchored,
           first.keptPosition?.containsSubstring("w:vertAnchor=\"text\"") == true,
           second.keptPosition?.containsSubstring("w:vertAnchor=\"text\"") == true,
           let fw = _columnWidths[before.table], let sw = _columnWidths[c.table], pgs.page > 0 {
            let fl = _tableLeft(before.table, document), sl = _tableLeft(c.table, document)
            let fr = fl + fw.reduce(0, +), sr = sl + sw.reduce(0, +)
            let clear = sl >= fr - 0.01 || sr <= fl + 0.01
            let runsOver = _beside_firstPage(of: before.table, upTo: pgs.page, text: true) < pgs.page
            if clear, runsOver,
               let top = _pages[pgs.page].filter({ _cells[$0.paragraph]?.table == before.table && !$0.repeated }).map(\.pageY).min(), top < pgs.y - 0.01 {
                RuleTrace.hit("word-floating-table-beside-a-floating-table-running-over-starts-level-with-its-rows-on-this-page")
                pgs.y = top
            }
        }
        // A floating table anchored to the text stands its offset
        // below the text's place (zh-64044a1d's equipment list,
        // 4.35pt under the line before it in Word's print).
        if theme.wordRules, c.row == 0, c.firstInRow, pgs.i == 0 || _cells[pgs.i - 1]?.table != c.table,
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
                var k = pgs.i
                while k < count, _cells[k]?.table == c.table { k += 1 }
                anchorFits = k < count && k < _heights.count && _cells[k] == nil && !_pageBreak[k]
                    && pgs.y + _heights[k] <= pgs.contentH + 0.01
            }
            if pgs.y > 0.01, pgs.y + _px(down) > pgs.contentH - 0.01 {
                if anchorFits { pgs.keptPastFoot = c.table } else { _pg_newPage(&pgs, document) }
            } else if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.y > 0.01, anchorFits, c.ownRowHeight > pgs.contentH - pgs.y - _px(down) + 0.01,
                      pgs.y + _px(down) >= _floatFootLimit(pgs.i, page: pgs.page, document) {
                // (Word for Windows sets a floating table's top no lower than the footer's place, the footer
                // distance and one empty line up from the page's foot: lab ovl2 autow's T34, tblpY 37 twips under
                // a line ending at 794.7, 17.7pt past that limit, goes whole to the next page in Word's print;
                // ours parted its first row at the foot.)
                _pg_newPage(&pgs, document)
            } else if theme.wordRules, RichTextTheme.wordWindowsPages, _columns > 1, pgs.y > 0.01, pgs.i < _sectionOf.count,
                      _columnsOf(paragraph: pgs.i) > 1 {
                // (In a section of columns Word keeps a floating table whole: where
                // the table, at its offset under the anchor, would run past the
                // column's foot by more than a few points, the anchor and the table
                // go to the next column together. Lab fm2 of lo-20f5d558: a 95pt
                // table at tblpY 472 twips moves from column 2 of page 1 to the top
                // of page 2's column 1; one that overruns by 3.6pt stays.)
                var tops = Double.infinity, bottoms = 0.0, k = pgs.i
                while k < count, let d = _cells[k], d.table == c.table {
                    tops = min(tops, d.rowTop); bottoms = max(bottoms, d.rowTop + d.ownRowHeight); k += 1
                }
                if bottoms > tops, pgs.y + _px(down) + (bottoms - tops) > pgs.contentH + _px(4) {
                    RuleTrace.hit("floating-table-in-columns-goes-whole-to-the-next-column")
                    _pg_newPage(&pgs, document)
                }
            }
            // (A run of floating tables hangs from one anchor, the
            // paragraph after the run: each stands its own offset
            // below that place, not below the one before it —
            // floating-tables-anchor, in Word's print.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.i > 0, let prevT = _cells[pgs.i - 1]?.table,
               let fb = pgs.floatRunBase, fb.table == prevT, fb.page == pgs.page,
               document.tableStyles[prevT]?.floatOffsetY != nil, document.tableStyles[prevT]?.pageAnchored != true {
                pgs.y = fb.y
            }
            // (Held where it stood before the text above it wrapped beside it: see `_floatPin`.)
            if let pin = _floatPin[c.table], pin.page == pgs.page, pin.y < pgs.y - 0.01 {
                RuleTrace.hit("word-float-keeps-its-place-when-the-text-before-it-wraps-beside-it")
                pgs.pinnedFrom = (c.table, pgs.page, pgs.y)
                pgs.y = pin.y
            }
            pgs.floatRunBase = (c.table, pgs.page, pgs.y)
            pgs.textFloatTop = (c.table, pgs.page, pgs.y, _px(down), false)
            pgs.besideChainEnd = nil
            if RichTextTheme.wordWindowsPages, document.tableStyles[c.table]?.keptPosition?.containsSubstring("w:tblpXSpec=\"right\"") == true {
                var lo = Double.infinity, hi = -Double.infinity, k = pgs.i
                while k < count, let d = _cells[k], d.table == c.table { lo = min(lo, d.rowTop); hi = max(hi, d.rowTop + d.ownRowHeight); k += 1 }
                if hi > lo { pgs.besideChainEnd = pgs.y + _px(down) + (hi - lo) }
            }
            // (A table that is the document's first block and holds a
            // drawing outside its cell is measured from the page's top
            // edge: LibreOffice's missing-path and tdf78727, tblpY 416
            // twips, have their drawing 20.8pt down the paper in Word's
            // print, 70pt over the margin where ours put it. One with
            // text only, do-not-break-wrapped-tables, stands at the
            // margin.)
            if RichTextTheme.wordWindowsPages, pgs.i == 0, pgs.page == 0, pgs.y < 0.01, _pages[pgs.page].isEmpty,
               document.tableStyles[c.table]?.shapesLeaveCell == true {
                let insetTop = _pageInsetTop.isEmpty ? 0 : _pageInsetTop[0]
                pgs.y = _px(down) - insetTop
            } else if RichTextTheme.wordWindowsPages, pgs.i > 0, _cells[pgs.i - 1] == nil, document.paragraphs[pgs.i - 1].text.isEmpty,
                      document.paragraphs[pgs.i - 1].image == nil, document.paragraphs[pgs.i - 1].style.frameXML == nil,
                      pgs.i == 1, pgs.page == 0, let before = _pages[pgs.page].last, before.paragraph == 0, before.pageY <= pgs.y + 0.01,
                      !{ () -> Bool in
                          // (Not where another floating table follows at once: the anchor of both is the paragraph after
                          // them, which stands under that empty line. LibreOffice's tdf97090, tblpY 941 and -36: the
                          // first table 47pt under the paragraph after, 126 on the page, ours 103.)
                          var k = pgs.i
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
                pgs.y = max(pgs.y, before.pageY + _px(down))
            } else if RichTextTheme.wordWindowsPages, (document.compatibilityMode ?? 12) >= 15, pgs.i > 0, _cells[pgs.i - 1] == nil,
                      let last = pgs.lastEmptyAt, last.i == pgs.i - 1, last.page == pgs.page, last.y < pgs.y - 0.01, pgs.y + _px(down) + c.ownRowHeight > pgs.contentH + 0.01, last.y + _px(down) + c.ownRowHeight <= pgs.contentH + 0.01, Self._tableBeforeEmptiesIsOn(page: pgs.page, i: pgs.i, cells: _cells, pieces: _pages[pgs.page]),
                      Self._followsFloatingTable(pgs.i, c.table, document: document, cells: _cells) {
                // (Compat 15, a table floating after another with empty lines between: it hangs
                // from the empty line just before it, 45pt under that line's baseline, not
                // from where the flow has got to. Lab anchor, Word for Windows.)
                RuleTrace.hit("compat15-second-floating-table-hangs-from-the-empty-line-before-it")
                pgs.y = last.y + _px(down)
            } else {
                pgs.y += _px(down)
            }
            // (A floating table that keeps text off (tblOverlap never) after another that does, sharing part of its width
            // (the run's anchor has them one level): it stands below that one's rows on this page, and goes to the next
            // where it does not fit there. Word's print of dx2 33a4668e, two right-hand tables one after the other: the
            // first fills page 7, the second stands on page 8 beside the left table; ours set it level with the first,
            // over it, and every pair after it was a page late.)
            var before = pgs.i - 1
            while before > 0, _cells[before] == nil, document.paragraphs[before].text.isEmpty, document.paragraphs[before].image == nil { before -= 1 }
            if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.i > 0, let prevT = _cells[before]?.table, prevT != c.table,
               let first = document.tableStyles[prevT], first.floatsOverText, !first.pageAnchored,
               let second = document.tableStyles[c.table], second.floatsOverText, !second.pageAnchored,
               second.keptPosition?.containsSubstring("tblOverlap w:val=\"never\"") == true,
               first.keptPosition?.containsSubstring("tblOverlap w:val=\"never\"") == true,
               let sw = _columnWidths[c.table] {
                let sl = _tableLeft(c.table, document)
                var foot: CGFloat = 0
                var rows: [PagePiece] = []
                for pc in _pages[pgs.page] where !pc.repeated {
                    guard let ot = _cells[pc.paragraph]?.table, ot != c.table else { continue }
                    guard let os = document.tableStyles[ot], os.floatsOverText, !os.pageAnchored,
                          os.keptPosition?.containsSubstring("tblOverlap w:val=\"never\"") == true,
                          let ow = _columnWidths[ot] else { continue }
                    let ol = _tableLeft(ot, document)
                    guard sl < ol + ow.reduce(0, +) - 0.01 && sl + sw.reduce(0, +) > ol + 0.01 else { continue }
                    rows.append(pc)
                    foot = max(foot, pc.pageY + (pc.flowBottom - pc.flowTop))
                }
                let shares = !rows.isEmpty
                if shares, !rows.isEmpty, foot > pgs.y - 0.01 {
                    RuleTrace.hit("word-never-overlap-floating-table-stands-below-the-float-it-shares-width-with")
                    pgs.y = max(pgs.y, foot)
                    // (Its first row goes whole to the next page where it does not fit under that foot, with the run's
                    // anchor: the table after it at the other margin then stands level with it there.)
                    if pgs.y + c.ownRowHeight > pgs.contentH + 0.01, pgs.y > 0.01 {
                        _pg_newPage(&pgs, document)
                        pgs.floatRunBase = (c.table, pgs.page, pgs.y)
                        if let tf = pgs.textFloatTop, tf.table == c.table { pgs.textFloatTop = (c.table, pgs.page, pgs.y, tf.down, tf.chained) }
                        pgs.y += _px(down)
                    }
                }
            }
        }
        // (And one placed above the text's place, at a page's head,
        // that much up into the top margin: zh-76700e5f's cover table,
        // tblpY -733 under frames that take no room, has "ICS
        // 67.080.20" at 34.5 in Word's print, 36.65pt over the
        // margin; ours stood it at the margin — and 177pt down.)
        _pg_raiseAtHead(&pgs, document, c)
        _pg_liftToFoot(&pgs, document, c)
        // (A table placed above the anchor's line, after one placed below it
        // that hangs from the same anchor, the paragraph after both: it
        // stands that far above the anchor's place, not above the first one's
        // foot, and the paragraph still goes back to the anchor's place.
        // LibreOffice's tdf97090, tblpY 941 and -36 twips at the right
        // margin: the heading at 372 with the second table at its head
        // and the first 47pt under it; ours stood the second under the
        // first's 700, and the heading under that.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, c.row == 0, c.firstInRow, pgs.i > 0, let prevT = _cells[pgs.i - 1]?.table, prevT != c.table,
           let fb = pgs.floatRunBase, fb.table == prevT, fb.page == pgs.page,
           let was = document.tableStyles[prevT], was.floatOffsetY != nil, !was.pageAnchored,
           let ts = document.tableStyles[c.table], !ts.pageAnchored, ts.floatOffsetY == nil, let up = ts.floatRaiseY, ts.floatsOverText {
            RuleTrace.hit("word-float-above-the-anchor-after-one-below-it-hangs-from-the-same-line")
            pgs.y = max(0, fb.y - _px(up))
            pgs.floatRunBase = (c.table, pgs.page, pgs.y)
            if let tf = pgs.textFloatTop, tf.table == prevT { pgs.textFloatTop = (c.table, pgs.page, tf.y, tf.down, false) }
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
        if theme.wordRules, c.row == 0, c.firstInRow, pgs.i > 0, _cells[pgs.i - 1]?.table != c.table, pgs.y > 0.01, pgs.deferredUnder.isEmpty,
           !(document.paragraphs[pgs.i - 1].style.sectionXML != nil && document.paragraphs[pgs.i - 1].style.sectionBreaksPage != false),
           let ts = document.tableStyles[c.table], !ts.pageAnchored, ts.floatOffsetY == nil, let up = ts.floatRaiseY {
            // (A line a point above the table's top is under it too:
            // floattable-anchor-next-page's third table, tblpY -269 twips,
            // has the line before it 0.55pt short of its top, and that
            // line stands under it, 481.4, in Word's print.)
            let target = pgs.y - _px(up)
            if target >= 0 {
                var moved: [PagePiece] = []
                var edge = pgs.y
                while let last = _pages[pgs.page].last, last.paragraph < pgs.i, _cells[last.paragraph] == nil, !last.repeated,
                      last.pageY >= target - _px(1) || edge - _px(document.paragraphs[last.paragraph].style.spaceAfter) - Self._multipleSlack(document.paragraphs[last.paragraph].style, last.paragraph < _heights.count ? _heights[last.paragraph] : 0) > target + 0.01 {
                    edge = last.pageY
                    moved.insert(_pages[pgs.page].removeLast(), at: 0)
                    if let k = _allPieces.lastIndex(of: moved[0]) { _allPieces.remove(at: k) }
                }
                if !moved.isEmpty {
                    pgs.deferredUnder = moved
                    pgs.deferredTable = c.table
                    pgs.reordered = true
                    pgs.y = target
                } else if RichTextTheme.wordWindowsPages, pgs.y - target < _px(8) {
                    // (Nothing reaches into it: the 1.5-spaced line above
                    // clears the raise with its glyphs, and the table still
                    // stands its raise up. lo-235e3561: rows at 591, ours 595.)
                    pgs.y = target
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
        let floatDrop = theme.wordRules && c.row == 0 && (pgs.i == 0 || _cells[pgs.i - 1]?.table != c.table)
            ? _px(document.tableStyles[c.table]?.floatOffsetY ?? 0) : 0
        let rowBreaksPage = !sectionBreakHandled && c.firstInRow && _pageBreak[pgs.i] && !document.paragraphs[pgs.i].style.pageBreakInline
            && !(document.paragraphs[pgs.i].style.breakEndsPrevious && pgs.i > 0 && document.paragraphs[pgs.i - 1].cell != nil)
            && (pgs.y - floatDrop > 0.01 || !_pages[pgs.page].isEmpty || (theme.wordRules && pgs.markOnPage))
        if theme.wordRules, c.row == 0, c.firstInRow, pgs.i == 0 || _cells[pgs.i - 1]?.table != c.table, !rowBreaksPage,
           case let ts0 = document.tableStyles[c.table], ts0?.pageOffsetY != nil || ts0?.marginOffsetY != nil || ts0?.bottomAligned == true {
            let physical = pgs.page / _columns
            let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
            let target = ts0?.pageOffsetY.map { _px($0) - insetTop } ?? _pg_bottomAlignedOffset(&pgs, document, c, pgs.i).map { _px($0) - insetTop } ?? (_px(ts0?.marginOffsetY ?? 0) - _headerPushBeyondMargin(physical))
            if target > pgs.y + 0.01, target < pgs.contentH - 0.01 {
                pgs.tableReturn = (c.table, pgs.y, pgs.page, target)
                if ts0?.bottomAligned == true { pgs.bottomTablePage = (c.table, pgs.page) }
                pgs.y = target
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
                    var whole = c.rowTop + c.ownRowHeight, k = pgs.i
                    while k < count, let d = _cells[k], d.table == c.table { whole = max(whole, d.rowTop + d.ownRowHeight); k += 1 }
                    let total = whole - c.rowTop
                    let height = total <= pageBottom + 0.01 ? total : c.ownRowHeight
                    // (Only a table anchored to the PAGE is set up to its edge; one anchored to the text or the margin is not:
                    // Word's print of lab tblstrip5 m_k45 leaves it where the text puts it.)
                    if ts0?.pageAnchored == true, pgs.y + c.ownRowHeight > pageBottom + 0.01, height <= pageBottom + 0.01 {
                        RuleTrace.hit("page-anchored-table-set-up-to-the-page-edge")
                        pgs.y = pageBottom - height - max(c.ruleBelow, _pg_ruleUnder(&pgs, document, c))
                        pgs.pageEdgeClamp = (c.table, pageBottom)
                        pgs.keptPastFoot = c.table
                    }
                    // (A tall table floating by the page or the text is set up by as much as its text overruns the page's
                    // EDGE: the line of a cell that straddles the edge, laid out unlifted, runs past it by `over`; the
                    // table rises by that, the largest cell deciding (a nested table's block is no text line and does not count: dx2 56e12a87's signature table at the edge leaves the table where it is), unless the overrun is past 0.4 cm, where the line
                    // goes over to the next page whole. Word's print of labs tblstrip5-8 (A4, no line grid): overruns
                    // 4.9 to 10.9pt lifted by 4.92 to 10.92, 11.4 and more by none, the 26.9pt line's 10.36 by 10.32.)
                    else if total > pageBottom - pgs.y + 0.01, pageSetup(forPage: physical).lineGridPitch == nil {
                        var over = 0.0, k = pgs.i, oneRow = true
                        while k < count, let d = _cells[k], d.table == c.table {
                            if abs(d.rowTop - c.rowTop) > 0.01 { oneRow = false }
                            if d.rowSpan == 1, !d.vertical, document.paragraphs[k].image?.name != "table" {
                                let g = geometry(k)
                                var top = g.textTop
                                for b in Self._lineBottoms(g.painter) {
                                    let bottom = pgs.y + (g.textTop + b - c.rowTop)
                                    if pgs.y + (top - c.rowTop) < pageBottom - 0.01, bottom > pageBottom + 0.01 { over = max(over, bottom - pageBottom) }
                                    top = g.textTop + b
                                }
                            }
                            k += 1
                        }
                        if oneRow, over > 0.01, over <= _px(Self.floatingTableLiftLimit) {
                            RuleTrace.hit("tall-floating-table-lifted-by-its-overrun-past-the-page-edge")
                            pgs.y -= over
                        }
                    }
                }
            } else if target < -0.01, pgs.y < 0.01, _pages[pgs.page].isEmpty, target > -insetTop {
                // (Over the top margin too, where the page opens
                // with it: zh-19dde9e7's report, a table placed
                // 58.25pt down a page whose margin is 72, has its
                // title row's text at 67 in Word's print; ours
                // stood at the margin, 15pt low.)
                pgs.y = target
            } else if theme.wordRules, target < -0.01, target > -insetTop, pgs.y > 0.01, pgs.deferredUnder.isEmpty, {
                // (A table wholly in the top margin, above where the text
                // begins, takes no room from it, wherever in the file it
                // stands: tdf92157's 22.5pt letter-head tag, placed 0.05pt
                // down the page, follows a paragraph and has the address
                // table under it 20pt higher in Word's print than ours.)
                var bottom = c.rowTop + c.ownRowHeight, k = pgs.i
                while k < count, let d = _cells[k], d.table == c.table { bottom = max(bottom, d.rowTop + d.ownRowHeight); k += 1 }
                return target + (bottom - c.rowTop) <= 0.01
            }() {
                pgs.tableReturn = (c.table, pgs.y, pgs.page, target)
                pgs.y = target
            } else if theme.wordRules, RichTextTheme.wordWindowsPages, target < -0.01, target > -insetTop, pgs.y > 0.01, pgs.deferredUnder.isEmpty,
                      document.tableStyles[c.table]?.pageAnchored == true,
                      _tableLeftRoom(c.table, document) >= _px(18),
                      let last = _pages[pgs.page].last, last.paragraph < pgs.i, _cells[last.paragraph] == nil, !last.repeated,
                      document.paragraphs[last.paragraph].image == nil, !document.paragraphs[last.paragraph].text.contains(where: { $0 != " " }) {
                // (A table placed a fraction above the body's top, after a blank line: it keeps its place and the blank
                // lines after it stand beside it. dx2 f22ada3a, table at 124.8 on a body that begins at 125.2.)
                RuleTrace.hit("page-anchored-table-over-the-body-top-after-a-blank-line-keeps-its-place")
                pgs.tableReturn = (c.table, pgs.y, pgs.page, target)
                pgs.y = target
            } else if theme.wordRules, target >= 0, target < pgs.y - 0.01, pgs.deferredUnder.isEmpty, {
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
                // (Empty paragraphs do not count where the table is page-anchored and leaves a strip to its right: Word sets them
                // there beside it, dx2 606199f1's eleven blank lines run on past its third table's place at x 520 and the table
                // stays on the page.)
                let stripRight = document.tableStyles[c.table]?.pageAnchored == true
                    && ((_tableFlowWidth[c.table] ?? width) - (_tableLeft(c.table, document) + (_columnWidths[c.table] ?? []).reduce(0, +)) >= _px(12))
                func besideBlank(_ q: Int) -> Bool {
                    stripRight && document.paragraphs[q].image == nil && !document.paragraphs[q].text.contains { $0 != " " }
                }
                let under = _pages[pgs.page].filter { $0.paragraph < pgs.i && _cells[$0.paragraph] == nil && !$0.repeated
                    && !besideBlank($0.paragraph) && $0.pageY + ($0.flowBottom - $0.flowTop) > target + 0.01 }
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
                let rowsInTheWay = _pages[pgs.page].contains {
                    guard $0.paragraph < pgs.i, let other = _cells[$0.paragraph], !$0.repeated, other.table != c.table,
                          // (Not a table that floats itself: two floating tables lay over each other in Word's print,
                          // lab ovl13, where a raised table's rows reach 150pt down and the page-anchored one at 84pt
                          // stays on the page.)
                          // (Nor one placed against the PAGE, unless this table forbids overlap: sa1 a56e81ec's two
                          // page-anchored tables at the same place both stand on page 3 in Word's print, one over
                          // the other; ours sent the second to page 4.)
                          !(theme.wordRules && document.tableStyles[other.table]?.floatsOverText == true),
                          !(theme.wordRules && RichTextTheme.wordWindowsPages && document.tableStyles[other.table]?.pageAnchored == true
                            && document.tableStyles[c.table]?.keptPosition?.containsSubstring("tblOverlap w:val=\"never\"") != true),
                          $0.pageY + ($0.flowBottom - $0.flowTop) > target + 0.01 else { return false }
                    let l = _tableLeft(other.table, document)
                    return l < myRight - 0.01 && myLeft < l + (_columnWidths[other.table] ?? []).reduce(0, +) - 0.01
                }
                // (Nor where the whole table stands on this page at its place and only the text before it reaches
                // down over that place: the table goes whole to the next page and the text stays. Word for Windows'
                // lab fltpage5, a 26pt title wrapping to a second line down to 93pt before a table at 60pt:
                // title alone on page 1, table on page 2. A 24pt title that ends above the place leaves it, and so does
                // text that fits within the first row's own height (a line that overlaps the place by a little: zh-3ab8a2fb,
                // lo-6a5857f2, lo-0dd5bc0a stay where they were).
                // Where the table would part, the text goes under its first row, as above.)
                var whole = c.rowTop + c.ownRowHeight, k = pgs.i
                while k < count, let d = _cells[k], d.table == c.table { whole = max(whole, d.rowTop + d.ownRowHeight); k += 1 }
                // (How far the text reaches past the place, not the sum of the lines that do: dx2 9baed400's text
                // reaches 82pt past a place, less than its table's first row of 84pt, and Word keeps the table with it.)
                let reach = (_pages[pgs.page].filter { $0.paragraph < pgs.i && _cells[$0.paragraph] == nil && !$0.repeated
                        && !besideBlank($0.paragraph) }
                    .map { $0.pageY + ($0.flowBottom - $0.flowTop) }.max() ?? target) - target
                // (Only a table that cannot stand whole below its place but can on a page of its own moves (zh-3ab8a2fb's 3-page table stays): Word's lab atmove prints keep a 2-row and a 5-row table
                // at their place with the title's second line beside them and move the 6-row one.)
                // (A table taller than any page, with text before it that reaches its place and does not fit under its first row: the text stays and the
                // whole table starts the next page, not its first row under the text (text that fits under the first row is taken there, zh-3ab8a2fb). xd f42177d2: a 54pt title over an 8-row table.)
                if RichTextTheme.wordWindowsPages, reach > 0.01, under > c.ownRowHeight + 0.01, whole - c.rowTop > pgs.contentH + 0.01, k - pgs.i > 1, target + c.ownRowHeight + line <= pgs.contentH + 0.01 {
                    RuleTrace.hit("page-anchored-table-taller-than-a-page-goes-whole-to-the-next-page-where-the-text-before-it-reaches-past-its-first-row")
                    return true
                }
                if RichTextTheme.wordWindowsPages, reach > 0.01, whole - c.rowTop <= pgs.contentH + 0.01, target + reach + (whole - c.rowTop) > pgs.contentH + 0.01, target + c.ownRowHeight + line <= pgs.contentH + 0.01 {
                    RuleTrace.hit("page-anchored-table-whole-goes-to-the-next-page-where-the-text-before-it-reaches-its-place")
                    return true
                }
                return rowsInTheWay || target + c.ownRowHeight + line + under > pgs.contentH + 0.01
            }() {
                _pg_newPage(&pgs, document)
                let physical = pgs.page / _columns
                let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
                let target = ts0?.pageOffsetY.map { _px($0) - insetTop } ?? (_px(ts0?.marginOffsetY ?? 0) - _headerPushBeyondMargin(physical))
                if target > pgs.y + 0.01, target < pgs.contentH - 0.01 {
                    pgs.tableReturn = (c.table, pgs.y, pgs.page, target)
                    pgs.y = target
                    // (A table moved whole to a new page is lifted until one of its possible cuts, a row's end or a line's
                    // under inside a row that may part, sits at the page's edge, taking the most table it can; not above the
                    // top margin plus the bottom margin, else it stays where it was set. Word for Windows' labs gridlift1-7
                    // and fltpage5-8, 43 prints within 0.02pt: page-2 tops 33.84 to 75.02 by bottom margin, 58.32 at pitch
                    // 12 and 24, 41.40 at 14, and the set place at 15, 20, 30 and 36. dx2 f42177d2 51.84.)
                    if RichTextTheme.wordWindowsPages, let ts1 = ts0 {
                        let pageBottom = _px(pageSetup(forPage: physical).height) - insetTop
                        let floor = _px(pageSetup(forPage: physical).marginBottom)
                        let rule = max(c.ruleBelow, _pg_ruleUnder(&pgs, document, c))
                        var cuts: [Double] = []
                        var k = pgs.i
                        while k < count, let d = _cells[k], d.table == c.table {
                            if d.rowSpan == 1 { cuts.append(d.rowTop + d.ownRowHeight - c.rowTop) }
                            if d.rowSpan == 1, !d.vertical, !ts1.rowsCantSplit.contains(d.row), !ts1.rowsExactHeight.contains(d.row),
                               document.paragraphs[k].image?.name != "table" {
                                let g = geometry(k)
                                let least = _px(ts1.rowHeights[d.row] ?? 0)
                                for b in Self._lineBottoms(g.painter) {
                                    cuts.append(d.rowTop - c.rowTop + max(least, g.textTop - d.rowTop + b + d.pad.bottom))
                                }
                            }
                            k += 1
                        }
                        let kept = cuts.map { pageBottom - $0 - rule }.filter { $0 >= floor - 0.01 && $0 <= target + 0.01 }
                        if let lo = kept.min() {
                            RuleTrace.hit("page-anchored-table-moved-whole-is-lifted-to-a-cut-at-the-page-edge")
                            pgs.y = lo
                            pgs.tableReturn = (c.table, pgs.tableReturn?.1 ?? pgs.y, pgs.page, lo)
                        }
                    }
                }
            } else if target >= 0, target < pgs.y - 0.01, pgs.deferredUnder.isEmpty {
                var moved: [PagePiece] = []
                // (A blank line that reaches a little past the place of a page-anchored table with a free strip beside it
                // stays where it is and the table keeps its place, as the blank lines after it do: dx2 f22ada3a's 1pt
                // line at 125.2 against a table at 124.8.)
                let tsA = document.tableStyles[c.table]
                let stripBeside = RichTextTheme.wordWindowsPages && tsA?.pageAnchored == true
                    && (_tableLeft(c.table, document) >= _px(12)
                        && (_tableFlowWidth[c.table] ?? width) - (_tableLeft(c.table, document) + (_columnWidths[c.table] ?? []).reduce(0, +)) >= _px(12))
                func blankLine(_ q: Int) -> Bool { document.paragraphs[q].image == nil && !document.paragraphs[q].text.contains { $0 != " " } }
                while let last = _pages[pgs.page].last, last.paragraph < pgs.i, _cells[last.paragraph] == nil, !last.repeated,
                      !(stripBeside && blankLine(last.paragraph)),
                      last.pageY + (last.flowBottom - last.flowTop) > target + 0.01 {
                    moved.insert(_pages[pgs.page].removeLast(), at: 0)
                    if let k = _allPieces.lastIndex(of: moved[0]) { _allPieces.remove(at: k) }
                    if last.pageY <= target + 0.01 { break }
                }
                if !moved.isEmpty {
                    pgs.deferredUnder = moved
                    pgs.deferredTable = c.table
                    pgs.reordered = true
                    pgs.y = target
                } else if stripBeside, let last = _pages[pgs.page].last, last.paragraph < pgs.i, _cells[last.paragraph] == nil, !last.repeated,
                          blankLine(last.paragraph), last.pageY + (last.flowBottom - last.flowTop) > target + 0.01 {
                    RuleTrace.hit("page-anchored-table-keeps-its-place-over-a-blank-line-reaching-it")
                    pgs.tableReturn = (c.table, pgs.y, pgs.page, target)
                    pgs.y = target
                } else if let last = _pages[pgs.page].last, last.paragraph < pgs.i, _cells[last.paragraph] != nil, !last.repeated,
                          _cells[last.paragraph]?.table != c.table {
                    // (Beside the rows above, not over them — see above: it
                    // stands at its offset and the flow goes on from where
                    // it stood.)
                    pgs.tableReturn = (c.table, pgs.y, pgs.page, target)
                    pgs.y = target
                }
            }
        }
        // A table row is one unbreakable block; every member gets the
        // row's piece so its text paints on the row's page.
        var j = pgs.i
        while j < count, let d = _cells[j], d.table == c.table, d.row == c.row { j += 1 }
        let rowBottom = c.rowTop + c.ownRowHeight
        pgs.resumeCursor = nil   // a row restarts whole
        // (A table that opens a section, after a section of columns whose breaks made its columns:
        // it stands under the longest of them, on the page they are on, as a paragraph would —
        // dx2 c96f6a72's balance sheet, under the report's two-column heading block, not in the
        // second column slot. The paragraph rule is in _paginate; a table row skips it.)
        if theme.wordRules, RichTextTheme.sectionColumnsFlow, _perSection, c.firstInRow, c.row == 0, pgs.i > 0, pgs.i < _sectionOf.count, _sectionOf[pgs.i] != _sectionOf[pgs.i - 1],
           _columnsOf(paragraph: pgs.i - 1) > 1, !_pageBreak[pgs.i], pgs.page % _columns > 0 || _pages[pgs.page].isEmpty == false {
            let first = (pgs.page / _columns) * _columns
            var seq: [PagePiece] = []
            for s in first ... max(pgs.page, min(first + _columns - 1, _pages.count - 1)) { seq += _pages[s] }
            let own = seq.filter { $0.paragraph < document.paragraphs.count && _sectionOf[$0.paragraph] == _sectionOf[pgs.i - 1] }
            let holdsBreak: (Int) -> Bool = { k in
                k + 1 < document.paragraphs.count && document.paragraphs[k].text.isEmpty && document.paragraphs[k].cell == nil
                    && document.paragraphs[k + 1].style.columnBreak && document.paragraphs[k + 1].style.pageBreakBefore
                    && document.paragraphs[k + 1].style.breakEndsPrevious
            }
            if own.contains(where: { document.paragraphs[$0.paragraph].style.columnBreak && document.paragraphs[$0.paragraph].style.pageBreakBefore }) {
                let blockBottom = own.filter { !holdsBreak($0.paragraph) }.map { $0.pageY + $0.height }.max() ?? 0
                if blockBottom > 0, blockBottom <= pgs.contentH + 0.01 {
                    pgs.page = first
                    pgs.y = blockBottom
                    pgs.columnFloor = (first / _columns, blockBottom)
                }
            }
        }
        // A row whose first paragraph breaks the page before it
        // opens a page as a paragraph's break would: the section
        // break on the paragraph before the table (its next
        // section opening on a new page), or the file's own
        // w:pageBreakBefore in the cell. A break character inside
        // a cell Word ignores. (Lab `sectbl` from bug65649's
        // package: the test record's table on its own page.)
        if !sectionBreakHandled, c.firstInRow, _pageBreak[pgs.i], !document.paragraphs[pgs.i].style.pageBreakInline,
           !(document.paragraphs[pgs.i].style.breakEndsPrevious && pgs.i > 0 && document.paragraphs[pgs.i - 1].cell != nil),
           !rowOpensThePage, pgs.y - floatDrop > 0.01 || !_pages[pgs.page].isEmpty || (theme.wordRules && pgs.markOnPage) {
            // (After a section's empty mark, which takes no room and leaves its page blank, a table
            // opening the next section starts the page after it — lo-0ceaa045, 1 page for Word's 2.)
            _pg_newPage(&pgs, document)
            // (In columns a page break goes on to the next page, not
            // the next column, for a table's first row as for a
            // paragraph's: tdf153136's second copy, a table after a
            // page-break paragraph in a two-column section, opens
            // Word's page 2; ours set it in page 1's second column.)
            // (A column break is the next column: lo-e311acbade7c85b8's
            // second table follows a paragraph that breaks the column.)
            if theme.wordRules, _columns > 1, !document.paragraphs[pgs.i].style.columnBreak,
               !(pgs.i > 0 && document.paragraphs[pgs.i - 1].style.columnBreak) {
                while pgs.page % _columns != 0 { _pg_newPage(&pgs, document) }
            }
            // (A table placed against the page, at its offset on the
            // page the break opened.)
            if theme.wordRules, c.row == 0, pgs.i == 0 || _cells[pgs.i - 1]?.table != c.table,
               case let ts0 = document.tableStyles[c.table], ts0?.pageOffsetY != nil || ts0?.marginOffsetY != nil {
                let physical = pgs.page / _columns
                let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
                let target = ts0?.pageOffsetY.map { _px($0) - insetTop } ?? (_px(ts0?.marginOffsetY ?? 0) - _headerPushBeyondMargin(physical))
                if target > pgs.y + 0.01, target < pgs.contentH - 0.01 {
                    pgs.tableReturn = (c.table, pgs.y, pgs.page, target)
                    pgs.y = target
                } else if theme.wordRules, RichTextTheme.wordWindowsPages, ts0?.pageAnchored == true, ts0?.pageOffsetY != nil,
                          target < -0.01, target > -insetTop, pgs.y < 0.01, _pages[pgs.page].isEmpty {
                    // (Up into the top margin too, on the page the break opened: sa1 b3ef470a's schedule, tblpY 53.9pt against
                    // an 85pt margin, has its title at 71.64 in Word's print, ours at the margin, 31pt low.)
                    RuleTrace.hit("page-anchored-table-after-a-page-break-stands-in-the-top-margin")
                    pgs.y = target
                }
            }
            // (A table floating by the text, its offset lost with the page it
            // was set on, stands that offset down the page the break opened,
            // and the paragraph it hangs from, the one after it, stands at
            // that page's top over it: dx2 8676db65, tblpY 918 twips after a
            // page-break paragraph; Word's print has the anchor empty line at
            // the margin, the table 45.9pt under it, and the next empty lines
            // under the table.)
            if floatDrop > 0.01, RichTextTheme.wordWindowsPages, pgs.y < 0.01 {
                RuleTrace.hit("word-text-floating-table-after-page-break-keeps-its-offset")
                pgs.floatRunBase = (c.table, pgs.page, pgs.y)
                pgs.textFloatTop = (c.table, pgs.page, pgs.y, floatDrop, false)
                pgs.y = floatDrop
            }
            // (And one placed above the text's place stands up in the
            // margin on the page the break opened: LibreOffice's
            // floating-table-section-break, a table 9.85pt up under
            // the section break, has its text at 58 in Word's print.)
            _pg_raiseAtHead(&pgs, document, c)
        _pg_liftToFoot(&pgs, document, c)
        }
        // (At a page's top the table goes on: its header row
        // again, and the cells merged down from above.)
        func goOn() {
            guard c.row > 0 else { return }
            if _pg_headerRows(&pgs, document, c.table) > 0 { _pg_repeatHeader(&pgs, document, of: c.table, before: pgs.i) }
            _pg_continueSpans(&pgs, document, into: pgs.i, c)
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
            guard theme.wordRules, c.row <= 1, c.firstInRow, pgs.y > 0.01, document.tableStyles[c.table]?.pageAnchored == true else { return nil }
            var bottom = rowBottom, next = c.row == 1 ? c.ownRowHeight : 0, second = rowBottom
            var k = j
            while k < count, let d = _cells[k], d.table == c.table {
                bottom = max(bottom, d.rowTop + d.ownRowHeight)
                if d.row <= 1 { second = max(second, d.rowTop + d.ownRowHeight) }
                if d.row == 1, next == 0 { next = d.ownRowHeight }
                k += 1
            }
            let under = pgs.deferredTable == c.table ? pgs.deferredUnder.reduce(0) { $0 + $1.flowBottom - $1.flowTop } : 0
            // (At the second row, y is the first row's foot.)
            let rest = bottom - c.rowTop
            // (Whole while it ends above the footer's place, its
            // margin or no: zh-0b87285b's 13-row list at its tblpY
            // ends 530.2pt down a 595pt page — margin at 523, footer
            // at 545.4 — all on page 6 in Word's print, where ours
            // kept its header row alone there. zh-6cd1befe's 26 rows
            // would end at 832.8, under its footer's 792.4 and on
            // the page, and Word parts them.)
            let setup = pageSetup(forPage: pgs.page / _columns)
            let edge = max(pgs.contentH, _px(setup.height - setup.footerDistance) - _bodyInsets(page: pgs.page / _columns, document).top)
            // (Only where its second row does not fit whole: lab
            // `pa19` (Word 16, zh-19dde9e7's seven-row table placed
            // 150pt down) keeps rows 0 to 5 on the page and takes the
            // tall row 6 alone to the next, though the whole would
            // end past the foot; ours set the first row alone.)
            // (Not a row taller than any page, which no page holds whole: it parts
            // here, from under the first row — LibreOffice's tdf172156, a 896pt
            // row of empty lines in a floating table 182pt down the page, starts
            // on page 1 in Word's print and goes on over page 2.)
            if pgs.y + (second - c.rowTop) > edge + 0.01 {
                if RichTextTheme.wordWindowsPages, c.row == 1, second - c.rowTop > pgs.contentH + 0.01 { RuleTrace.hit("row-taller-than-a-page-parts-where-it-stands"); return nil }
                return (true, 0)
            }
            if under > 0, pgs.y + rest + under + next > pgs.contentH + 0.01 { return (false, rest) }
            return nil
        }
        let partsAfterFirst = c.row == 0 && anchoredParts() != nil && j < count && _cells[j]?.table == c.table
        if c.row == 1, let parts = anchoredParts() {
            if parts.whole {
                _pg_newPage(&pgs, document)
            } else {
                // (The cells merged down from the first row go on
                // from its foot, not from under that text.)
                let foot = pgs.y
                // (No lower than lets it stand on this page: zh-60173bb6's
                // "附件1" title, three 28.8pt lines before a table placed
                // 248.5pt down whose whole would end past the foot, is at
                // that page's foot in Word's print, 626-685, the table's
                // first row above it and the rest on the next page; ours
                // set it under the whole and took it to a page of its own.)
                let held = pgs.deferredUnder.reduce(0.0) { $0 + $1.flowBottom - $1.flowTop }
                pgs.y += theme.wordRules && pgs.contentH - foot - held >= 0 ? min(parts.under, pgs.contentH - foot - held) : parts.under
                _pg_placeDeferred(&pgs, document)
                pgs.y = foot
                _pg_newPage(&pgs, document)
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
        if theme.wordRules, c.row == 0, c.firstInRow, pgs.y > 0.01, pgs.i > 0, let before = _cells[pgs.i - 1]?.table, before != c.table,
           let ts = document.tableStyles[c.table], ts.floatsOverText, !ts.pageAnchored,
           let kept = ts.keptPosition, let at = kept.rangeOfSubstring("w:tblpY=\""),
           let raised = Double(kept[at.upperBound...].prefix { $0 == "-" || $0.isNumber }), raised <= 0 {
            var bottom = rowBottom, k = j
            while k < count, let d = _cells[k], d.table == c.table { bottom = max(bottom, d.rowTop + d.ownRowHeight); k += 1 }
            let whole = bottom - c.rowTop
            // (Whole while it ends above the footer's place, as a
            // table placed against the page: its 649pt end 7pt
            // past the margin on page 15, over the footer's 49.6.)
            let setup = pageSetup(forPage: pgs.page / _columns)
            let edge = max(pgs.contentH, _px(setup.height - setup.footerDistance) - _bodyInsets(page: pgs.page / _columns, document).top)
            if pgs.y + whole > edge + 0.01, whole <= edge - 0.01 { _pg_newPage(&pgs, document); _pg_raiseAtHead(&pgs, document, c) }
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
        let carried = c.row == 0 && pgs.i > 0 && _cells[pgs.i - 1] == nil && document.paragraphs[pgs.i - 1].style.keepNext
        // (A row is kept with the next only where the first paragraph of
        // every one of its cells says so: lo floattable-header's "A2: page
        // 2" is Heading 1, which keeps with the next, beside a cell that
        // does not, and Word's print leaves the row on page 2 under the
        // header row, where ours took it to page 3 and left page 2 empty.
        // Only in a floating table: lab lab75 (Word, modes 14 and 15), in a
        // table in the flow, keepNext in the FIRST cell alone keeps the row
        // with the next; in the second cell alone it does not.)
        var rowKept = document.paragraphs[pgs.i].style.keepNext
        // (In a table in the flow the FIRST cell is the one that counts; a
        // row whose first cell is a vertical merge continuation has no
        // paragraph there, and the next cell's keepNext does not keep the
        // row: zh-9e08ed28's rows over "3、推廣", the heading style in the
        // second cell, stay on page 15 in Word's print.)
        if rowKept, theme.wordRules, RichTextTheme.wordWindowsPages, c.column > 0, document.tableStyles[c.table]?.keptPosition == nil {
            rowKept = false; RuleTrace.hit("zh9e08-first-cell-merged-keeps-nothing")
        }
        if rowKept, theme.wordRules, RichTextTheme.wordWindowsPages, _cells[pgs.i] != nil, document.tableStyles[c.table]?.keptPosition != nil {
            var m = pgs.i
            while m < count, let e = _cells[m], e.table == c.table, e.row == c.row {
                if m == pgs.i || _cells[m - 1]?.column != e.column, !document.paragraphs[m].style.keepNext { rowKept = false; RuleTrace.hit("row-kept-only-if-every-cell-keeps") }
                m += 1
            }
        }
        if theme.wordRules, c.firstInRow, pgs.y > 0.01, !carried, rowKept {
            var previous: Int? = nil
            var b = pgs.i - 1
            while b >= 0, let d = _cells[b], d.table == c.table, d.row == c.row - 1 { previous = b; b -= 1 }
            if !(previous.map { document.paragraphs[$0].style.keepNext } ?? false) {
                var k = pgs.i, row = c.row
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
                // (A run of kept rows that ends the table keeps with the
                // paragraph after it: 75f0f9d1's three rows of keepNext
                // in the first cell, then a paragraph of a page break,
                // go whole to page 28 in Word's print, where the first
                // two stood on 27 and the third alone went over.)
                if follower == nil, theme.wordRules, RichTextTheme.wordWindowsPages, k < count, _cells[k] == nil,
                   document.tableStyles[c.table]?.keptPosition == nil {
                    var bottom = rowBottom, m = j
                    while m < count, let d = _cells[m], d.table == c.table { bottom = max(bottom, d.rowTop + d.ownRowHeight); m += 1 }
                    let g = geometry(k)
                    let kst = document.paragraphs[k].style
                    let bottoms = Self._lineBottoms(g.painter)
                    // (Under widow control a paragraph of two or three lines does
                    // not part, so all its lines are needed beside the table:
                    // e60b34e0's header rows then "ARTÍCULO 2" of two lines fit
                    // page 7's foot by one line and go whole to page 8 in Word.)
                    let wholeLines = !kst.keepLines && kst.widowControl && !document.widowControlSuspended && bottoms.count >= 2 && bottoms.count <= 3
                    let first = document.paragraphs[k].image != nil ? _heights[k]
                        : (wholeLines ? bottoms[bottoms.count - 1] : (bottoms.first ?? _heights[k]))
                    follower = (bottom, (g.textTop - g.top) + first)
                    RuleTrace.hit("kept-last-row-keeps-with-the-paragraph-after")
                }
                if let follower {
                    let need = follower.top - c.rowTop + follower.height
                    if pgs.y + need > pgs.contentH + 0.01 { _pg_newPage(&pgs, document) }
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
        if keepsWhole, c.firstInRow, c.row == 0, pgs.y > 0.01 {
            var bottom = rowBottom, k = j
            while k < count, let d = _cells[k], d.table == c.table { bottom = max(bottom, d.rowTop + d.ownRowHeight); k += 1 }
            let whole = bottom - c.rowTop
            if pgs.y + whole > pgs.contentH + 0.01, whole <= pgs.contentH - 0.01 { _pg_newPage(&pgs, document) }
        }
        let atTop = pgs.y < 0.01
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
            for piece in _pages[pgs.page] where piece.part != .rules && piece.paragraph < pgs.i && !piece.repeated {
                let m = piece.paragraph
                guard let d = _cells[m], d.table == c.table, d.row < c.row, !d.vertical,
                      (c.row ... c.row + c.ghostRows).contains(d.row + d.rowSpan - 1) else { continue }
                if piece.part == .text { continued = true }
                need = max(need, piece.pageY + (min(piece.flowBottom, _tops[m] + _heights[m]) - piece.flowTop) + d.pad.bottom - pgs.y)
            }
            // (Taller than the flow made it, too: a cell that left
            // one line with the row above and took four over the
            // page asks this row for all four.)
            return continued ? max(c.ownRowHeight - c.stretched, need) : c.ownRowHeight
        }
        // (Under a pinned float that it would run into: see
        // `_pinnedFloats`.)
        if c.firstInRow { _pg_underPins(&pgs, document, c.ownRowHeight) }
        var shown = pageHeight()
        // (`STARLING_RICHTEXT_ROWS=<page>` prints each row as it
        // is set on that page: where it stands, what is left,
        // and what it asks.)
        if let traced = Self.debugRows, traced == pgs.page + 1 {
            let line = "row \(c.row) of \(c.table) at \(pgs.i): y \(pgs.y / _px(1))pt of \(pgs.contentH / _px(1)), shown \(shown / _px(1)), own \(c.ownRowHeight / _px(1)), rule under \(_pg_ruleUnder(&pgs, document, c) / _px(1)), top \(atTop)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
        pgs.wentOver = false
        // (Down to the footer's place: zh-5a9a85c6's first row ends
        // at 792.0, the footer's place 792.4.)
        var pastFoot = keepsWhole && c.row > 0 && pgs.y > 0.01
        if pgs.keptPastFoot == c.table, c.row == 0 {
            let setup = pageSetup(forPage: pgs.page / _columns)
            let edge = pgs.pageEdgeClamp?.table == c.table ? pgs.pageEdgeClamp!.edge : _px(setup.height - setup.footerDistance) - _bodyInsets(page: pgs.page / _columns, document).top
            // (A row taller than the body cannot be kept whole past the foot: it parts, as Word does with
            // dx2 bede0fbc's 694pt wrapper row, whose remainder went missing when kept.)
            pastFoot = pgs.y + shown + _pg_ruleUnder(&pgs, document, c) <= edge + 0.01 && shown <= pgs.contentH + 0.01
        } else if pgs.keptPastFoot == c.table {
            pgs.keptPastFoot = nil
        }
        // (A row of a table placed from the margin (a float naming no w:vertAnchor) stays where it ends within the
        // page's footer edge, the one a table placed against the page is set up to: dx2 a6254f44's and 54d1d1d1's
        // last row, 460 twips at least, ends 2.3pt under the foot on page 21 in Word's print; ours took it to a
        // 22nd page. A floating table by the text is not so kept: 9fc782eb's row 26 goes over in Word's print.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, !pastFoot, !atTop, c.firstInRow, document.tableStyles[c.table]?.marginOffsetY != nil,
           document.tableStyles[c.table]?.keptPosition != nil, shown + _pg_ruleUnder(&pgs, document, c) > pgs.contentH - pgs.y + 0.01,
           case let setup = pageSetup(forPage: pgs.page / _columns),
           pgs.y + shown + _pg_ruleUnder(&pgs, document, c) <= _px(setup.height - setup.footerDistance) - _bodyInsets(page: pgs.page / _columns, document).top + 0.01 {
            RuleTrace.hit("margin-placed-floating-table-row-ending-within-the-footer-edge-stays-at-the-foot")
            pastFoot = true
        }
        // (The same for a floating table set by the text, its row, set at its offset, ending within the page: dx2 491931cb's
        // picture table, tblpY 1042 twips, ends 26pt under the foot at 796 of 842 on page 2 in Word's
        // print, its anchor heading above it there; ours took it whole to page 3 and the heading after it.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, !pastFoot, !atTop, c.firstInRow, c.row == 0,
           let ts = document.tableStyles[c.table], let down = ts.floatOffsetY, down > 0, !ts.pageAnchored,
           shown + _pg_ruleUnder(&pgs, document, c) > pgs.contentH - pgs.y + 0.01,
           case let setup = pageSetup(forPage: pgs.page / _columns),
           pgs.y + shown + _pg_ruleUnder(&pgs, document, c) <= _px(setup.height) - _bodyInsets(page: pgs.page / _columns, document).top + 0.01 {
            RuleTrace.hit("word-text-anchored-floating-table-row-ending-within-the-page-stays-at-the-foot")
            pastFoot = true
        }
        if theme.wordRules, !pastFoot, shown + _pg_ruleUnder(&pgs, document, c) > pgs.contentH - pgs.y + 0.01, _pg_splitRow(&pgs, document, pgs.i, j, c, atTop: atTop) {
            // (A row that ends at the margin leaves the next of a page-anchored table in compat 12 to part by lines to the
            // page's own foot, where it is the table's own and begun here: lo-c9b8c5ab's A4 ends 468.1 of 468 and A5
            // stands four lines on page 1 in Word's print.)
            let nextParts = RichTextTheme.wordWindowsPages && (document.compatibilityMode ?? 12) < 15 && j < count
                && document.tableStyles[c.table]?.pageAnchored == true && _cells[j]?.table == c.table
                && document.tableStyles[c.table]?.rowHeights[_cells[j]!.row].map({ _cells[j]!.ownRowHeight > _px($0) + _px(2) }) ?? true
                && pgs.y < _px(pageSetup(forPage: pgs.page / _columns).height) - _bodyInsets(page: pgs.page / _columns, document).top - _px(14)
            if pgs.y > pgs.contentH - 0.01, !_pg_tableEndsOverAnchor(&pgs, document, c, j), !nextParts { _pg_newPage(&pgs, document) }
            pgs.i = j
            return
        }
        if pgs.wentOver {
            // (The row went to a new page whole: there it is laid
            // out again, and parted if the page cannot hold it.)
            // (A floating table placed up over the text, taken to the
            // new page whole, stands that much up there too:
            // floattable-next-leaf-in-section's second table, tblpY
            // -289 under a table that fills page 1, has its first
            // line 12pt over the margin on page 2 in Word's print;
            // ours stood it at the margin.)
            _pg_raiseAtHead(&pgs, document, c)
            // (A floating table's first row taken whole to the next page by its own part stands its offset
            // down that page too, as one taken there before it is set: lab compat1415b rows19, compat 14,
            // A1 at 66.0 on page 2 with tblpY 323 twips.)
            if theme.wordRules, c.row == 0, c.firstInRow, pgs.y < 0.01, pgs.i == 0 || _cells[pgs.i - 1]?.table != c.table,
               let down = document.tableStyles[c.table]?.floatOffsetY, down > 0, !(document.tableStyles[c.table]?.pageAnchored ?? false),
               // (Not when the row, clamped to the page, would then no longer fit: lo-a48482e7's A2 fills page 3 and
               // stands there in Word's print under its 1-twip offset.)
               pageHeight() + _pg_ruleUnder(&pgs, document, c) + _px(down) <= pgs.contentH + 0.01 {
                RuleTrace.hit("floating-table-first-row-carried-whole-stands-its-offset-down")
                pgs.y += _px(down)
            }
        _pg_liftToFoot(&pgs, document, c)
            _pg_underPins(&pgs, document, c.ownRowHeight)
            shown = pageHeight()
            if shown + _pg_ruleUnder(&pgs, document, c) > pgs.contentH - pgs.y + 0.01, _pg_splitRow(&pgs, document, pgs.i, j, c, atTop: true) {
                if pgs.y > pgs.contentH - 0.01 { _pg_newPage(&pgs, document) }
                pgs.i = j
                return
            }
        } else if !atTop, !pastFoot, shown + _pg_ruleUnder(&pgs, document, c) > pgs.contentH - pgs.y + 0.01, pgs.y > 0.01 {
            _pg_newPage(&pgs, document)
            // (A floating table's first row taken to the next page
            // stands its offset down that page too: zh-0243e7fc's
            // p11 form, tblpY 272 twips under text, has its first
            // line 13pt lower in Word's print than ours at the top.)
            if theme.wordRules, c.row == 0, c.firstInRow, pgs.i == 0 || _cells[pgs.i - 1]?.table != c.table,
               let down = document.tableStyles[c.table]?.floatOffsetY, !(document.tableStyles[c.table]?.pageAnchored ?? false) {
                // (The run's anchor goes with it: the table after, at the other margin, hangs from the same level on this
                // page, not from where the first stood on the one before. dx2 33a4668e, tblOverlap never: a right-hand
                // table carried whole to the next page has the left-hand one beside it there in Word's print.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, let fb = pgs.floatRunBase, fb.table == c.table,
                   document.tableStyles[c.table]?.keptPosition?.containsSubstring("tblOverlap w:val=\"never\"") == true {
                    RuleTrace.hit("word-never-overlap-floating-table-carried-whole-takes-its-run-anchor-with-it")
                    pgs.floatRunBase = (c.table, pgs.page, pgs.y)
                    if let tf = pgs.textFloatTop, tf.table == c.table { pgs.textFloatTop = (c.table, pgs.page, pgs.y, tf.down, tf.chained) }
                }
                // (The text beside it hangs from the new page's anchor too, not the old page's.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, let tf = pgs.textFloatTop, tf.table == c.table, tf.page != pgs.page {
                    RuleTrace.hit("floating-table-carried-whole-takes-its-beside-text-anchor-with-it")
                    pgs.textFloatTop = (c.table, pgs.page, pgs.y, tf.down, false)
                    pgs.besideChainEnd = nil
                    if document.tableStyles[c.table]?.keptPosition?.containsSubstring("w:tblpXSpec=\"right\"") == true {
                        var lo = Double.infinity, hi = -Double.infinity, k = pgs.i
                        while k < count, let d = _cells[k], d.table == c.table { lo = min(lo, d.rowTop); hi = max(hi, d.rowTop + d.ownRowHeight); k += 1 }
                        if hi > lo { pgs.besideChainEnd = pgs.y + _px(down) + (hi - lo) }
                    }
                }
                pgs.y += _px(down)
            }
            // (And one placed against the page stands at its offset
            // on the page it went to — up into the top margin too:
            // zh-0513f641's p9 form, tblpY 1322 against a 1440
            // margin after the cover that fills p8, has its top line
            // at 66.0 in Word's print; ours stood it at the margin.)
            if theme.wordRules, c.row == 0, c.firstInRow, pgs.i == 0 || _cells[pgs.i - 1]?.table != c.table,
               case let ts0 = document.tableStyles[c.table], ts0?.pageOffsetY != nil || ts0?.marginOffsetY != nil, _pages[pgs.page].isEmpty {
                let physical = pgs.page / _columns
                let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
                let target = ts0?.pageOffsetY.map { _px($0) - insetTop } ?? (_px(ts0?.marginOffsetY ?? 0) - _headerPushBeyondMargin(physical))
                if target > pgs.y + 0.01, target < pgs.contentH - 0.01 {
                    pgs.tableReturn = (c.table, pgs.y, pgs.page, target)
                    pgs.y = target
                } else if target < -0.01, target > -insetTop {
                    pgs.y = target
                }
            }
            // (A table placed up over the text taken to this page
            // from the foot of the last stands up there too: the
            // floattable-tab-join pair and floattable-object-formatter,
            // tblpY -179 twips on a landscape page, have the second
            // table start 9pt up in the margin on page 2 in Word's
            // print and keep all three rows there; ours stood it at
            // the margin and sent the third row to page 3.)
            _pg_raiseAtHead(&pgs, document, c)
        _pg_liftToFoot(&pgs, document, c)
            goOn()
            _pg_underPins(&pgs, document, c.ownRowHeight)
            shown = pageHeight()
        } else if theme.wordRules, !atTop, pgs.y > 0.01, j < count, _cells[j] == nil, document.paragraphs[pgs.i].style.keepNext,
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
            if shown + _pg_ruleUnder(&pgs, document, c) + need > pgs.contentH - pgs.y + 0.01 {
                _pg_newPage(&pgs, document)
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
        if theme.wordRules, pgs.y < 0.01, c.firstInRow, case let extra = _pg_headLift(&pgs, document, pgs.i, j, c, wholeRow: true), extra > 0.01,
           shown + extra + _pg_ruleUnder(&pgs, document, c) <= pgs.contentH + 0.01 {
            pgs.y += extra
        }
        // (A row at a page's head whose every cell says nil above, in a table with no top line of its own, has no line
        // over it: the line under the row before stays on the page before, and the row is that line's room shorter with
        // its text as much higher. sa1 8b5747ec's date row, 27.6pt in Word's print, ours 28.55.)
        var headDrop = 0.0
        if theme.wordRules, RichTextTheme.wordWindowsPages, pgs.y < 0.01, c.firstInRow, c.row > 0, c.rules > 0.01, shown >= c.ownRowHeight - 0.01,
           let ts = document.tableStyles[c.table], !(ts.edges?.top ?? (ts.borders && !ts.bordersFromCells)),
           (pgs.i ..< j).allSatisfy({ k in
               document.paragraphs[k].cell.map { d in
                   let xml = d.bordersXML ?? ""
                   return (xml.containsSubstring("<w:top w:val=\"nil\"") || xml.containsSubstring("<w:top w:val=\"none\"")) && d.edges?.top != true } ?? false
           }) {
            RuleTrace.hit("word-row-opening-a-page-under-nil-tops-has-no-line-over-it")
            headDrop = c.rules
            shown -= headDrop
        }
        if abs(shown - c.ownRowHeight) > 0.01 {
            // Its cells' text from where each stands in a row of
            // that height, and its rules: their last stretch with
            // the line under it, under as much of their middle
            // as a taller row needs.
            let spare = c.ownRowHeight - shown
            let edge = min(_px(2), c.ownRowHeight / 4)
            for k in pgs.i ..< j {
                let d = _cells[k]!
                let down = d.rowSpan > 1 ? 0 : headDrop + (d.verticalAlign == "center" ? (spare - headDrop) / 2 : d.verticalAlign == "bottom" ? spare - headDrop : 0)
                var text = PagePiece(paragraph: k, flowTop: c.rowTop + down,
                                     flowBottom: d.rowSpan > 1 ? c.rowTop + d.rowHeight : c.rowTop + down + shown, page: pgs.page, pageY: pgs.y)
                text.part = .text
                _pg_add(&pgs, document, text)
                guard k == pgs.i else { continue }
                var at = pgs.y, left = shown
                while left > c.ownRowHeight + 0.01 {
                    let top = at == pgs.y ? c.rowTop : c.rowTop + edge
                    let take = min(rowBottom - edge - top, left - edge)
                    var middle = PagePiece(paragraph: pgs.i, flowTop: top, flowBottom: top + take, page: pgs.page, pageY: at)
                    middle.part = .rules
                    middle.inner = true
                    _pg_add(&pgs, document, middle)
                    at += take
                    left -= take
                }
                var rules = PagePiece(paragraph: pgs.i, flowTop: rowBottom - left, flowBottom: rowBottom, page: pgs.page, pageY: at)
                rules.part = .rules
                rules.inner = true
                _pg_add(&pgs, document, rules)
            }
            pgs.y += shown
            if pgs.y > pgs.contentH - 0.01 { _pg_newPage(&pgs, document) }
            pgs.i = j
            return
        }
        // A cell merged down, centred or set at the bottom, whose
        // rows do not all fit on this page is set in the rows that
        // do: zh-6d1afa56's "工程建设项目招标投标信息" spans rows 5
        // and 6, row 6 goes to the next page, and Word centres the
        // four lines in row 5 — where centring them over both put
        // them 40pt low, half of them over the page's foot.
        var lift: [Int: Double] = [:]
        if theme.wordRules, (pgs.i ..< j).contains(where: { _cells[$0]!.rowSpan > 1 }) {
            // The rows below, as tall as each stands, while they fit.
            var heights: [Int: Double] = [c.row: c.ownRowHeight]
            var n = j
            while n < count, let d = _cells[n], d.table == c.table {
                if heights[d.row] == nil { heights[d.row] = d.ownRowHeight }
                n += 1
            }
            var column: [Int: (first: Int, last: Int)] = [:]
            for k in pgs.i ..< j { let d = _cells[k]!; column[d.column] = (column[d.column]?.first ?? k, k) }
            // What of row `r`, after `part` of a merge on this
            // page, stays on the page where the row parts at its
            // foot (0 where it goes over whole).
            func partingKept(_ r: Int, after part: Double) -> Double {
                guard let first = (j ..< count).first(where: { _cells[$0]?.table == c.table && _cells[$0]?.row == r }),
                   let e = _cells[first], document.tableStyles[c.table]?.rowsCantSplit.contains(r) != true,
                   !document.paragraphs[first].style.keepNext,
                   _px(document.tableStyles[c.table]?.rowHeights[r] ?? 0) <= pgs.contentH - pgs.y - part - _pg_ruleUnder(&pgs, document, e, parted: true) + 0.01 else { return 0 }
                    // (The line that closes the page, as `splitRow` cuts the row by it:
                    // zh-e1b09977's "農委會", merged over a row that parts under the table's
                    // 2.16 bottom line, stands in the nine lines that stay, 9pt higher than
                    // the ten the smaller line counted.)
                    let closing = theme.wordRules && RichTextTheme.wordWindowsPages ? _pg_ruleClosing(&pgs, document, e) : _pg_ruleUnder(&pgs, document, e, parted: true)
                    let limit = e.rowTop + (pgs.contentH - pgs.y - part) - closing + 0.01
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
                        return e.ghostBounds.last(where: { $0 + _pg_ruleUnder(&pgs, document, e) <= pgs.contentH - pgs.y - part + 0.01 }) ?? 0
                    }
                    // (Only where the row does part there: every cell
                    // of it keeps a line on the page, else it goes
                    // over whole — see `splitRow`.)
                    var kept = 0.0
                    var columns: [Int: Bool] = [:]   // column → keeps something here
                    var n = first
                    while n < count, let f = _cells[n], f.table == c.table, f.row == r {
                        if f.rowSpan == 1, !f.vertical {
                            let cut = _pg_cellCuts(&pgs, document, n).last(where: { $0 <= limit && $0 > e.rowTop + 0.01 })
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
                    return kept > 0 && columns.values.allSatisfy({ $0 }) ? min(max(kept, stated), pgs.contentH - pgs.y - part) : 0
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
                      part + h + _pg_ruleUnder(&pgs, document, c, across: true) <= pgs.contentH - pgs.y + 0.01 { part += h; r += 1 }
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
                      part + h + _pg_ruleUnder(&pgs, document, c, across: true) <= pgs.contentH - pgs.y + 0.01 { part += h; r += 1 }
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
                if Self.debugRows == pgs.page + 1 {
                    FileHandle.standardError.write(Data("centred-span cell \(g.first): part \(part / _px(1)) rowHeight \(d.rowHeight / _px(1)) rows \(c.row)..\(r) of \(d.rowSpan) partsAfterFirst \(partsAfterFirst) avail \((pgs.contentH - pgs.y) / _px(1))\n".utf8))
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
                        for cut in _pg_cellCuts(&pgs, document, k) where cut - _tops[g.first] <= room + 0.01 { shown = max(shown, cut - _tops[g.first]) }
                    }
                    if shown > 0 {
                        // (Word centres the lines that stay in the part, even when that is lower
                        // than the whole span's centre: zh-38d26944's "成果精度", one 26pt line
                        // of three, in a 45pt row at page 12's foot, 9.5 down in Word's print.)
                        let want = free / 2 - (room - shown) / 2
                        up = theme.wordRules && RichTextTheme.wordWindowsPages ? want : max(0, want)
                    }
                    if Self.debugRows == pgs.page + 1 {
                        FileHandle.standardError.write(Data("centred-part cell \(g.first): part \(part / _px(1)) free \(free / _px(1)) text \(text / _px(1)) room \(room / _px(1)) shown \(shown / _px(1)) cuts \((g.first ... g.last).map { k in _pg_cellCuts(&pgs, document, k).map { ($0 - _tops[g.first]) / _px(1) } })\n".utf8))
                    }
                }
                for k in g.first ... g.last { lift[k] = up }
            }
        }
        for k in pgs.i ..< j {
            // A cell spanning rows paints through every row it covers.
            let bottom = _cells[k]!.rowSpan > 1 ? c.rowTop + _cells[k]!.rowHeight : rowBottom
            guard let up = lift[k], abs(up) > 0.01 else {
                _pg_add(&pgs, document, PagePiece(paragraph: k, flowTop: c.rowTop, flowBottom: bottom, page: pgs.page, pageY: pgs.y))
                continue
            }
            // (Its text lifted, its shading and rules where they were.)
            var text = PagePiece(paragraph: k, flowTop: c.rowTop + up, flowBottom: bottom, page: pgs.page, pageY: pgs.y)
            text.part = .text
            _pg_add(&pgs, document, text)
            var rules = PagePiece(paragraph: k, flowTop: c.rowTop, flowBottom: bottom, page: pgs.page, pageY: pgs.y)
            rules.part = .rules
            rules.inner = true
            _pg_add(&pgs, document, rules)
        }
        pgs.y += c.ownRowHeight
        // (What follows a table floating by the text keeps its bottomFromText clear of it: Word
        // for Windows' print of LibreOffice's lo-7cba9019, 43 twips, puts the second floating table
        // 2.1pt and the normal table under it 2.3pt lower than ours, which ignored the distance.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, j >= count || _cells[j]?.table != c.table,
           let gap = document.tableStyles[c.table]?.floatBottomGap { pgs.y += _px(gap) }
        // (A table floating by the text with no offset (tblpYSpec top), after an empty paragraph: that
        // empty paragraph's line stands under the table as well, Word's print of lab fltafter
        // (A: no empty paragraph after the table still has its 9pt line under it at x 50.4; the same
        // table inline has none): 10.9pt under a 9pt empty before it.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, (document.compatibilityMode ?? 12) >= 15, j >= count || _cells[j]?.table != c.table,
           let ts = document.tableStyles[c.table], ts.floatsTopByText, !ts.pageAnchored {
            var k0 = pgs.i
            while k0 > 0, _cells[k0 - 1]?.table == c.table { k0 -= 1 }
            if k0 > 0, _cells[k0 - 1] == nil, document.paragraphs[k0 - 1].text.isEmpty, document.paragraphs[k0 - 1].image == nil,
               document.paragraphs[k0 - 1].style.frameXML == nil {
                RuleTrace.hit("word-floating-table-by-text-repeats-the-empty-before-it-under-it")
                pgs.y += _heights[k0 - 1]
            }
        }
        if pgs.y > pgs.contentH - 0.01, !_pg_tableEndsOverAnchor(&pgs, document, c, j) { _pg_newPage(&pgs, document) }
        pgs.i = j
    }
}
