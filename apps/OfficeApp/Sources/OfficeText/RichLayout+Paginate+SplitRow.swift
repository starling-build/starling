// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paginate+SplitRow": steps of `_paginate`, once nested functions of it (a pure move: the variables
// they shared are `_PState`, passed inout).

import Flutter
import FlutterSwiftBridge
import Foundation

private struct _SplitColumn { var members: [Int]; var cuts: [Double]; var bottom: Double; var cut: Double; var owners: [Int] = []; var slacks: [Double] = [] }

extension RichLayout {
    func _pg_splitRow(_ pgs: inout _PState, _ document: RichDocument, _ i: Int, _ j: Int, _ c: _CellGeo, atTop: Bool) -> Bool {
        let ts = document.tableStyles[c.table]
        // (A row marked as a header never parts, repeated or not:
        // zh-e37f8d40's form marks every row, so none repeats, and
        // Word carries its 民政局社会救助股意见 row whole to page 14
        // where ours parted it three lines and two.)
        // (Nor a row of exact height that a page could hold: zh-340d52e9's
        // 347pt "守望相助" row (hRule exact) goes whole to page 6 in
        // Word's print with 58pt left on page 5, where ours parted it.)
        guard let ts, !ts.rowsCantSplit.contains(c.row), c.row >= _pg_headerRows(&pgs, document, c.table),
              !(theme.wordRules && ts.headerRow && c.row < ts.headerRowCount),
              !(theme.wordRules && ts.rowsExactHeight.contains(c.row) && c.ownRowHeight <= pgs.contentH + 0.01) else { return false }
        // (Nor a row of a floating table that holds an anchored picture the text wraps round, when a page could hold it: 99a68284's row goes
        // whole to the next page in Word's print, where ours parted it at the foot.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, !atTop, ts.keptPosition != nil || ts.floatOffsetY != nil, c.ownRowHeight <= pgs.contentH + 0.01,
           (i ..< j).contains(where: { k in let q = document.paragraphs[k]; return (q.inlineImages.inOrder + [q.image].compactMap({ $0 })).contains(where: { $0.float?.wraps == true }) }) {
            RuleTrace.hit("floating-table-row-with-an-anchored-picture-goes-whole")
            return false
        }
        // (Nor an exact-height row taller than the page that starts at a page's top:
        // sa1 173f0cb1's 720pt row stays whole there in Word's print, clipped at the
        // foot, where ours parted it and made a third page.)
        if theme.wordRules, atTop, ts.rowsExactHeight.contains(c.row) { return false }
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
        if theme.wordRules, document.paragraphs[i].style.keepNext, ts.keptPosition == nil, c.ownRowHeight <= pgs.contentH + 0.01 { return false }
        // (Nor a row with a table floating in one of its cells, that a page could hold: lo-5c5eb1f7's
        // "26" row, a float table in each of two cells, goes whole to page 6 in Word's print
        // where ours parted it at page 5's foot.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, c.ownRowHeight <= pgs.contentH + 0.01 {
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
        if theme.wordRules, !atTop, !_pages[pgs.page].allSatisfy({ $0.repeated }), let footer = _headerFooter(.footer, page: pgs.page, document, pageCount: 1),
           footer.document.paragraphs.contains(where: { p in
               p.cell == nil && p.style.frame.map { $0.y < 0 && ($0.width != nil || (p.style.frameXML ?? "").containsSubstring("w:wrap=\"around\"")) } == true }),
           _bodyInsets(page: pgs.page, document).bottom > _px(pageSetup(forPage: pgs.page).marginBottom) + 0.01 {
            return false
        }
        // (A turned cell does not keep its row whole: zh-021b8feb's
        // "職場人力協助" row, its first cell turned (tbRlV), parts at
        // page 17's foot in Word's print, where ours took it whole to
        // page 18 and the table ran onto a 19th.)
        if !theme.wordRules { for k in i ..< j { guard let d = _cells[k], !d.vertical else { return false } } }
        var fresh = atTop
        let rowBottom = c.rowTop + c.ownRowHeight
        // (The top margins and lines of the nested cells a part that goes over a page is still in: it is
        // set under them again — see `RichParagraphStyle.nestedTopRepeat`.)
        func nestedRepeat(_ column: _SplitColumn) -> Double {
            guard theme.wordRules, let k = column.members.first(where: { _tops[$0] + _heights[$0] > column.cut + 0.01 }) else { return 0 }
            return _px(document.paragraphs[k].style.nestedTopRepeat)
        }
        // (What a part that goes on to the next page is held clear of the foot by, besides the nested cells' own
        // bottoms: the outer cell's top margin under its rule and the nested tops, which the next part stands
        // under again — Word ends lo-c7082c66's page 3 a line sooner than the bottoms alone allow; 0.3 of the cell's top margin more is fitted to lab nf1
        // (Word for Windows, margins 0 / 113 / 300 twips: pages 1-3 end where Word's do; a flat 3pt broke the 0 one).)
        func nestedGap(_ column: _SplitColumn) -> Double {
            let r = nestedRepeat(column)
            guard r > 0 else { return 0 }
            return r + max(0, _cells[column.members[0]]!.pad.top - _pg_ruleUnder(&pgs, document, c, parted: true)) + 0.3 * _cells[column.members[0]]!.pad.top
        }
        // (A flattened row, a floating table's, is no shorter than its least height on EACH page its part stands on:
        // lab nf1, Word for Windows — the last part of lo-c7082c66's float row, six lines on page 4, stands 169.6pt
        // tall, its least height, and the cell's next paragraphs under that.)
        func partPad(_ column: _SplitColumn) -> (at: Double, amount: Double)? {
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
        var columns: [_SplitColumn] = []
        for k in i ..< j {
            let d = _cells[k]!
            if columns.isEmpty || _cells[columns[columns.count - 1].members[0]]!.column != d.column {
                columns.append(_SplitColumn(members: [], cuts: [], bottom: 0, cut: c.rowTop))
            }
            columns[columns.count - 1].members.append(k)
            let own = _pg_cellCuts(&pgs, document, k)
            columns[columns.count - 1].cuts.append(contentsOf: own)
            columns[columns.count - 1].owners.append(contentsOf: repeatElement(k, count: own.count))
            columns[columns.count - 1].slacks.append(contentsOf: _pg_cellSlacks(&pgs, document, k))
            // (A cell merged down has the rows below for the rest.)
            columns[columns.count - 1].bottom = d.rowSpan > 1 ? min(rowBottom, _tops[k] + _heights[k] + d.pad.bottom)
                : _tops[k] + _heights[k] + d.pad.bottom
        }
        let repeats = c.row > 0 && _pg_headerRows(&pgs, document, c.table) > 0
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
            var avail = pgs.contentH - pgs.y
            // (A table floating by the text and raised over its place, up past the
            // margin: Word sets the page's room by the place it would have stood,
            // not the raised one, so the page ends as much sooner as the raise.
            // LibreOffice's lo-1709e655, tblpY -345 twips, one cell of 60 lines:
            // 48 on the page in Word's print, 50 in ours.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, first, let ts = document.tableStyles[c.table],
               ts.floatsOverText, ts.floatOffsetY == nil, !ts.pageAnchored, let up = ts.floatRaiseY, ts.rowsExactHeight.isEmpty,
               let top = _pages[pgs.page].filter({ !$0.repeated && _cells[$0.paragraph]?.table == c.table }).map(\.pageY).min(), top < -0.01,
               // (A table taller than the page only: one that ends on it keeps
               // its room — lo-3b33e295's two small raised tables.)
               case let whole = (0 ..< count).compactMap({ k in _cells[k].flatMap { $0.table == c.table ? $0.rowTop + $0.ownRowHeight : nil } }).max() ?? 0,
               whole > pgs.contentH + 0.01, c.ownRowHeight > avail + 0.01, _columnWidths[c.table]?.count == 1 {
                avail -= min(_px(up), -top)
            }
            // (A table placed against the page and raised over the margin, taller than
            // the page, in 2013's layout: Word gives it the body's height from the
            // place it stands, not from the margin, so its first page ends as much
            // sooner as the raise: 3667057e's 23-row floating table, tblpY 17.35pt
            // on a 595pt page with the margin at 85, cuts its second row after
            // 4 lines at 478 in Word for Windows' print; ours went to the foot, 550.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, first, (document.compatibilityMode ?? 12) >= 15,
               let ts = document.tableStyles[c.table], ts.pageAnchored, ts.pageOffsetY != nil, ts.rowsExactHeight.isEmpty,
               let top = _pages[pgs.page].filter({ !$0.repeated && _cells[$0.paragraph]?.table == c.table }).map(\.pageY).min(), top < -0.01,
               case let whole = (0 ..< count).compactMap({ k in _cells[k].flatMap { $0.table == c.table ? $0.rowTop + $0.ownRowHeight : nil } }).max() ?? 0,
               whole > pgs.contentH + 0.01, c.ownRowHeight > avail + 0.01 {
                avail -= -top
            }
            // (A table placed against the page whose rows from here on
            // end above the footer's place sets them on this page, past
            // the margin: zh-0b87285b's 13-row list ends 524.9pt down a
            // 595pt page in Word for Windows' print, margin at 523 and
            // footer at 545.4 — `anchoredParts` keeps its head with it,
            // and ours sent its last row alone to page 7, its title
            // after it.)
            // (A one-row table floating by the text or the margin runs its lines to the page's edge as a page-anchored one does: dx2 56e12a87's
            // row, tblpY 59pt under the margin, keeps lines to 816.6 and blank ones to 837.5 on a 841.9pt page in Word's print; ours stopped at the margin, 793.7.)
            let textFloatOneRow: Bool = {
                guard theme.wordRules, RichTextTheme.wordWindowsPages, first, c.row == 0,
                      let ts = document.tableStyles[c.table], !ts.pageAnchored, ts.marginOffsetY != nil else { return false }
                // (Set by the text a line or less under its anchor, the row flows as the text does and ends at the margin: lo-148591d5
                // and lo-c98d1eaf, tblpY 1 twip, break at the margin in Word's print, as 56e12a87's, 59pt down, does not.)
                // (A table set by the text, 20 to 420 twips under its anchor, flows and breaks at the margin too: lab thr, Word for Windows, compat 12,
                // a ten-line row 1 to 21 pt under an anchor line 17 pt above the margin keeps 2 lines (20, 60 twips), 1 line (120 to 300) or none (420) on page 1.
                // Only a margin-anchored table, 56e12a87's, runs to the edge.)
                return !_cells.contains { $0?.table == c.table && $0!.row > 0 }
            }()
            if theme.wordRules, first, document.tableStyles[c.table]?.pageAnchored == true || textFloatOneRow {
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
                let setup = pageSetup(forPage: pgs.page / _columns)
                let edge = pgs.pageEdgeClamp?.table == c.table ? pgs.pageEdgeClamp!.edge : max(pgs.contentH, _px(setup.height - setup.footerDistance) - _bodyInsets(page: pgs.page / _columns, document).top)
                // (Not far past the margin: LibreOffice's floattable-then-table, a
                // page-anchored table of two 200pt rows on a page whose margin is
                // 123pt, has its second row 70pt over the margin and above the
                // footer's place, and Word's print parts it onto page 2; the 26pt
                // of floattable-compat14 stays.)
                // (And a row that parts by lines goes on to the footer's place as well, where the table
                // starts on this page: LibreOffice's floattable-avoid-last-manip-ofst, a landscape 612pt page,
                // margin at 540 and footer at 576.6, keeps three more lines of a row on page 1 in Word for
                // Windows' print, at 536.9, 550.3 and 563.7; its pages 2 to 5 stop at 515, whole rows.)
                let startsHere = c.row == 0 || _pages[pgs.page].contains { piece in
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
                    let limit = stated ? pgs.contentH + _px(66.5) : _px(setup.height - 14) - _bodyInsets(page: pgs.page / _columns, document).top
                    avail = max(avail, max(edge, limit) - pgs.y)
                } else if byLines || pgs.y + (bottom - c.rowTop) <= edge + 0.01 && (c.row == 0 || pgs.y + (bottom - c.rowTop) - pgs.contentH <= _px(40)) && !(RichTextTheme.wordWindowsPages && (document.compatibilityMode ?? 12) >= 15 && c.row > 0) { avail = max(avail, edge - pgs.y) }
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
                for piece in _pages[pgs.page] where piece.part != .rules && piece.paragraph < i && !piece.repeated {
                    let m = piece.paragraph
                    guard let d = _cells[m], d.table == c.table, d.row < c.row, !d.vertical,
                          (c.row ... c.row + c.ghostRows).contains(d.row + d.rowSpan - 1) else { continue }
                    carried = max(carried, piece.pageY + (min(piece.flowBottom, _tops[m] + _heights[m]) - piece.flowTop) + d.pad.bottom - pgs.y)
                }
            }
            let left = max(carried, columns.map { column in
                // (With the cell's top margin under the rule again —
                // see where the pieces are set below.)
                max(0, column.bottom + (partPad(column)?.amount ?? 0) - column.cut)
                    + (theme.wordRules ? max(0, _cells[column.members[0]]!.pad.top - _pg_ruleUnder(&pgs, document, c, parted: true)) + nestedRepeat(column) : 0)
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
                : max(theme.wordRules && left + _pg_ruleUnder(&pgs, document, c) <= avail + 0.01 ? min(stated, avail - _pg_ruleUnder(&pgs, document, c)) : stated, left, ghostLeft)
            // (A part, or the row on the next page, goes under a pinned
            // float it would run into, as a whole row does.)
            if !pgs.pinBands.isEmpty {
                _pg_underPins(&pgs, document, rest)
                avail = pgs.contentH - pgs.y
            }
            var fits = rest + _pg_ruleUnder(&pgs, document, c) <= avail + 0.01
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
            if let traced = Self.debugRows, traced == pgs.page + 1 {
                FileHandle.standardError.write(Data("split row \(c.row): first \(first) fresh \(fresh) y \(pgs.y / _px(1)) stated \(stated / _px(1)) avail \(avail / _px(1)) fits \(fits) rest \(rest / _px(1)) ghostBounds \(c.ghostBounds.map { $0 / _px(1) })\n".utf8))
            }
            // (A row that opens a page of a table with no top line of its own
            // does not keep the room of the inside line above it, which Word
            // neither draws nor reserves there: zh-37b6536f p5, row 12 under
            // outset inside lines, 0.9pt high in ours.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, first, fresh, pgs.y < 0.01, c.firstInRow, c.row > 0, !repeats,
               let ts = document.tableStyles[c.table], ts.edges?.top == false, c.rules > 0.01, c.rules <= _px(2) {
                pgs.y -= c.rules
            }
            if first, !fresh, pgs.y > 0.01, stated > 0, stated + max(_pg_ruleUnder(&pgs, document, c), theme.wordRules ? c.ruleBelow : 0) > avail + 0.01 {
                _pg_newPage(&pgs, document)
                if repeats { _pg_repeatHeader(&pgs, document, of: c.table, before: i) }
                if c.row > 0 { _pg_continueSpans(&pgs, document, into: i, c) }
                pgs.wentOver = true
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
               let bound = c.ghostBounds.last(where: { $0 + _pg_ruleUnder(&pgs, document, c) <= avail + 0.01 }) {
                // (With the rule a part closes with, whole: zh-9ef811c8's "8" row, a
                // 15.6pt row and the 0.5 over it, stands on page 6 with its one-line cells and
                // its marks in Word's print, the merged lists of ten lines all on page 7.)
                avail = bound + (RichTextTheme.wordWindowsPages ? max(_pg_ruleUnder(&pgs, document, c), _pg_ruleUnder(&pgs, document, c, parted: true)) : _pg_ruleUnder(&pgs, document, c))
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
                    let room = avail - _pg_ruleUnder(&pgs, document, c, parted: true) - d0.pad.top - d0.pad.bottom - (blockBottom - blockTop)
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
                    let limit = start + avail - _pg_ruleClosing(&pgs, document, c) + 0.01
                    let partsAnyway = fresh && c.ownRowHeight + _pg_ruleUnder(&pgs, document, c) > avail + 0.01
                    if room < -0.01, (!fresh && pgs.y > 0.01) || partsAnyway, columns[n].cuts.contains(where: { $0 > start + 0.01 && $0 <= limit }) {
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
                    // (A table with cell spacing closes a part under the cell margin and the spacing twice over, as it opens
                    // one: its first baseline is 2.25pt down from the page's top for a 0.75 margin and 0.75 spacing, and
                    // Word's print of xs 19be02d9, a one-cell table of a decree, ends every page's part 16.1pt short of
                    // where ours put a 43rd line, 726.7 against a 728.5 foot with the cell's own margin alone counted; the foot keeps the table's margin and twice the spacing, 2.25pt.)
                    let spacedFoot: Double = {
                        guard RichTextTheme.wordWindowsPages, theme.wordRules, let ts = document.tableStyles[c.table], let sp = ts.cellSpacing, sp > 0 else { return 0 }
                        // (The page a part goes on to opens with the same 2.25pt, which the cut does not carry: Word's p2 and p3 of 19be02d9 hold 44 lines like p1.)
                        let once = _px(2 * sp) + max(0, _px(ts.cellMarginBottom ?? 0) - (_cells[column.members[0]]?.margin ?? 0))
                        return column.cut > c.rowTop + 0.01 ? 2 * once : once
                    }()
                    let contTop = RichTextTheme.wordWindowsPages && theme.wordRules && document.tableStyles[c.table]?.keptPosition != nil && column.cut > c.rowTop + 0.01 ? _cells[column.members[0]]!.pad.top : 0
                    let limit = column.cut + avail - _pg_ruleUnder(&pgs, document, c, parted: true) - bottomMargin - contTop + 0.01
                    // (A cut, under the line the part is closed with —
                    // where the cell ends here, its own bottom has it.)
                    // (To Word for Windows' raster: it sets rows on a 1/600in grid
                    // from the running total (lab round), so a cut that rounds to the
                    // foot's dot is on the page — zh-4c5da793 p15's row "对抚恤优待对象
                    // 冒领…" keeps its second line in Word's print, 0.09pt past ours,
                    // its row standing 0.11 high.)
                    let closed = column.cut + avail - _pg_ruleClosing(&pgs, document, c) - bottomMargin - contTop + 0.01
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
                    let room = avail - _pg_ruleUnder(&pgs, document, c, parted: true) - d0.pad.top - d0.pad.bottom - (blockBottom - blockTop)
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
                        setWhole[n] = pgs.y + d0.pad.top + max(0, room) * (d0.verticalAlign == "center" ? 0.5 : 1) - blockTop
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
                    } else if let at = column.cuts.indices.last(where: { column.cuts[$0] > column.cut + 0.01 && column.cuts[$0] - (column.slacks.indices.contains($0) ? column.slacks[$0] : 0) <= closed - (theme.wordRules && bottomMargin == 0 ? (((document.compatibilityMode ?? 12) >= 15 && d0.rowSpan == 1 && column.cuts[$0] < column.bottom - d0.pad.bottom - 0.01 && !_cells.contains { $0?.table == d0.table && ($0?.rowSpan ?? 1) > 1 }) ? 0 : d0.margin) + spacedFoot : 0) - (theme.wordRules && bottomMargin == 0 && (document.compatibilityMode ?? 12) >= 15 ? (column.cuts[$0] >= column.bottom - d0.pad.bottom - 0.01 ? d0.pad.bottom : (d0.rowSpan == 1 && !_cells.contains { $0?.table == d0.table && ($0?.rowSpan ?? 1) > 1 } ? max(0, d0.pad.bottom - d0.ruleBelow) : 0)) : 0) - nestedFoot(column.owners.indices.contains($0) ? column.owners[$0] : -1) - nestedGap(column) }),
                              case let owner = column.owners.indices.contains(at) ? column.owners[at] : -1,
                              let cut = column.cuts.indices.filter({ $0 >= at && (column.owners.indices.contains($0) ? column.owners[$0] : -1) == owner })
                                .last(where: { column.cuts[$0] - (column.slacks.indices.contains($0) ? column.slacks[$0] : 0) <= cutClosed - (theme.wordRules && bottomMargin == 0 ? (((document.compatibilityMode ?? 12) >= 15 && d0.rowSpan == 1 && column.cuts[$0] < column.bottom - d0.pad.bottom - 0.01 && !_cells.contains { $0?.table == d0.table && ($0?.rowSpan ?? 1) > 1 }) ? 0 : d0.margin) + spacedFoot : 0) - (theme.wordRules && bottomMargin == 0 && (document.compatibilityMode ?? 12) >= 15 ? (column.cuts[$0] >= column.bottom - d0.pad.bottom - 0.01 ? d0.pad.bottom : (d0.rowSpan == 1 && !_cells.contains { $0?.table == d0.table && ($0?.rowSpan ?? 1) > 1 } ? max(0, d0.pad.bottom - d0.ruleBelow) : 0)) : 0) - nestedFoot(column.owners.indices.contains($0) ? column.owners[$0] : -1) - nestedGap(column) }).map({ column.cuts[$0] }) {
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
                        if let traced = Self.debugRows, traced == pgs.page + 1 {
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
                                setWhole[n] = pgs.y + d0.pad.top + max(0, room) * (d0.verticalAlign == "center" ? 0.5 : 1) - blockTop
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
                if let traced = Self.debugRows, traced == pgs.page + 1 {
                    FileHandle.standardError.write(Data("after-columns row \(c.row): moved \(moved) stuck \(stuck) cols \(columns.map { "[\($0.members[0]) cut \($0.cut / _px(1)) bottom \($0.bottom / _px(1)) cuts \($0.cuts.map { $0 / _px(1) })]" }) next \(next.map { $0 / _px(1) }) rowBottom \(rowBottom / _px(1)) setWhole \(setWhole.count) avail \(avail / _px(1))\n".utf8))
                }
                if !moved {
                    if !fresh, pgs.y > 0.01 {
                        // Not a line of it fits here: the row starts the next page.
                        // (Where it opens that page whole, its centred cells
                        // are centred again — see the start moved above.)
                        if first { for n in columns.indices { columns[n].cut = c.rowTop } }
                        _pg_newPage(&pgs, document)
                        fresh = true
                        if repeats { _pg_repeatHeader(&pgs, document, of: c.table, before: i) }
                        if c.row > 0 { _pg_continueSpans(&pgs, document, into: i, c) }
                        // (Under the table's top line there: see `headLift`.)
                        // (A parted frame too, where the row opens the page whole: sa1 67e19017 p6, 1pt.)
                        if pgs.y < 0.01 { pgs.y += _pg_headLift(&pgs, document, i, j, c, wholeRow: true) }
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
                pgs.prevPartBottom = below && theme.wordRules && RichTextTheme.wordWindowsPages
                    && columns.indices.contains(where: { _cells[columns[$0].members[0]]!.rowSpan == 1 && next[$0] < rowBottom - 0.01 }) ? pgs.y + part : nil
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
                                      let last = _pg_cellCuts(&pgs, document, m).last(where: { $0 <= c.rowTop + avail + 0.01 }) else { continue }
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
                        let onPage = _allPieces.indices.filter { _allPieces[$0].page == pgs.page && members.contains(_allPieces[$0].paragraph) && _allPieces[$0].part != .rules && !_allPieces[$0].repeated }
                        guard let first0 = onPage.first else { continue }
                        // (Not text that goes on from the page before: its lines stand where the cut left them, at the
                        // part's head, level with the row's own first line. Lab cm4 and zh-9ba2ead7 p8, whose "房屋及设施
                        // 设备…" block ours moved 36pt up, above the margin.)
                        if theme.wordRules, _allPieces[first0].flowTop > top + 0.01 { continue }
                        // (Where the text stands now, by its piece; where it should stand, by the row's page y.)
                        let nowAt = _allPieces[first0].pageY + (top - _allPieces[first0].flowTop)
                        let wantAt = pgs.y + (d.rowTop + d.pad.top + max(0, free) * 0.5 - c.rowTop)
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
            var rule = PagePiece(paragraph: i, flowTop: from - lift, flowBottom: min(rowBottom, from + shown), page: pgs.page, pageY: pgs.y - lift)
            rule.part = .rules
            rules.append(rule)
            _pages[pgs.page].append(rule)
            for (n, column) in columns.enumerated() {
                if doneWhole.contains(n) { continue }
                if let at = setWhole[n] {
                    doneWhole.insert(n)
                    for k in column.members {
                        var piece = PagePiece(paragraph: k, flowTop: _tops[k], flowBottom: _tops[k] + _heights[k], page: pgs.page, pageY: at + _tops[k])
                        piece.part = .text
                        pieces[k, default: []].append(piece)
                        _pages[pgs.page].append(piece)
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
                    // (A text box that goes on stands under its cell's top margin AND the rule, not the margin overlapping the rule as
                    // plain text does: Word's print of sa1 03f63881, a 1pt margin under a 1pt white rule, takes the continued box's
                    // first line 1pt lower, 0.75 on the scaled page, on pages 14 and 15.)
                    let boxed = RichTextTheme.wordWindowsPages && document.paragraphs[k].image?.textBox != nil
                    let again = !first && theme.wordRules ? (boxed ? _cells[column.members[0]]!.pad.top : max(0, _cells[column.members[0]]!.pad.top - _pg_ruleUnder(&pgs, document, c, parted: true))) + nestedRepeat(column) : 0
                    var piece = PagePiece(paragraph: k, flowTop: lo, flowBottom: hi, page: pgs.page, pageY: pgs.y + (lo - column.cut) + (shift[n] ?? 0) + again + (fits ? ((partPad(column).map { lo >= $0.at - 0.01 ? $0.amount : 0 }) ?? 0) : 0))
                    piece.part = .text
                    pieces[k, default: []].append(piece)
                    _pages[pgs.page].append(piece)
                }
            }
            pgs.y += shown
            if fits { break }
            for n in columns.indices { columns[n].cut = next[n] }
            first = false
            _pg_newPage(&pgs, document)
            fresh = true
            if repeats { _pg_repeatHeader(&pgs, document, of: c.table, before: i) }
            if c.row > 0 { _pg_continueSpans(&pgs, document, into: i, c) }
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
                lift = Self._rowOpensBare(i, j, document) ? 0 : _pg_ruleUnder(&pgs, document, c, parted: true)
                if lift > 0, !repeats { lift = max(lift, lift + _pg_headLift(&pgs, document, i, j, c)) }
                pgs.y += lift
            }
            // (The notes marked in what this page will hold of the row.)
            if theme.wordRules, !pgs.rowPending.isEmpty {
                let width = _pg_noteWidth(&pgs, document)
                var here: [Int] = []
                var room = 0.0
                for id in pgs.rowPending {
                    guard let k = (i ..< j).first(where: { _footnotes(in: $0, document).contains(id) }),
                          let n = columns.firstIndex(where: { $0.members.contains(k) }),
                          let mark = _footnoteMarkLine(k, id, document), let note = _note(id, width: width, document) else { here.append(id); continue }
                    room += note.height + (pgs.pageNotes.isEmpty && here.isEmpty ? _note(-1, width: width, document)?.height ?? 0 : 0)
                    if pgs.y + (mark.bottom - columns[n].cut) + room > pgs.contentH + 0.01 { break }
                    here.append(id)
                }
                pgs.rowPending.removeAll { here.contains($0) }
                _pg_reserveNotes(&pgs, document, here)
            }
        }
        // (In paragraph order, the rules after their paragraph's text.)
        for k in i ..< j {
            _allPieces.append(contentsOf: pieces[k] ?? [])
            if k == i { _allPieces.append(contentsOf: rules) }
        }
        return true
    }
}
