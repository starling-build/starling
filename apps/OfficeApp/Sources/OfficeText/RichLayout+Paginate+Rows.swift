// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paginate+Rows": steps of `_paginate`, once nested functions of it (a pure move: the variables
// they shared are `_PState`, passed inout).

import Flutter
import FlutterSwiftBridge
import Foundation

private struct _InnerPiece { var row: Int; var column: Int; var cuts: [Double]; var bottom: Double }

extension RichLayout {
    func _pg_lineUnderRow(_ pgs: inout _PState, _ document: RichDocument, _ c: _CellGeo) -> Double {
        if let rows = pgs.linesUnderRows[c.table] { return rows[c.row] ?? 0 }
        var rows: [Int: Double] = [:]
        for d in _cells {
            guard let d, d.table == c.table else { continue }
            rows[d.row + d.rowSpan - 1] = max(rows[d.row + d.rowSpan - 1] ?? 0, d.ruleNext)
        }
        pgs.linesUnderRows[c.table] = rows
        return rows[c.row] ?? 0
    }

    func _pg_ruleUnder(_ pgs: inout _PState, _ document: RichDocument, _ c: _CellGeo, parted: Bool = false, across: Bool = false) -> Double {
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
        let line = max(0, spansOn ? _pg_lineUnderRow(&pgs, document, c) : c.ruleNext)
        if RichTextTheme.wordWindowsPages, !half, line > _px(1), line > bottom + 0.01 { return line / 2 }
        return max(0, spansOn ? _pg_lineUnderRow(&pgs, document, c) : c.ruleNext, (document.compatibilityMode ?? 12) >= 14 ? bottom : 0) / (half ? 2 : 1)
    }

    // What a row's part at a page's foot is closed with there: its
    // top line's width, as `_pg_ruleUnder(&pgs, document, parted:)` has it — and in the
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
    func _pg_headLift(_ pgs: inout _PState, _ document: RichDocument, _ i: Int, _ j: Int, _ c: _CellGeo, wholeRow: Bool = false) -> Double {
        guard theme.wordRules, c.row > 0, let ts = document.tableStyles[c.table],
              ts.edges?.top ?? (ts.borders && !ts.bordersFromCells),
              !(RichTextTheme.wordWindowsPages && !wholeRow && Self._partedFrame(ts)),
              (i ..< j).contains(where: { k in
                  document.paragraphs[k].cell.map { d in !(d.bordersXML ?? "").containsSubstring("<w:top ") && d.edges?.top == nil } ?? false
              }) || Self._rowHasContinuedTopUnsaid(i, document) else { return 0 }
        return max(0, _px(Self._ruleRoom(ts.edgeStyles["top"] ?? ts.borderStyle, ts.edgeWidths["top"] ?? ts.borderWidth ?? 0.5)) - max(0, c.rules - c.ruleBelow))
    }

    // (Cells merged down from the page before whose text all goes over to this page, none of it left on the page before:
    // they open it with the row, under the table's top line. Word's print of sa1 bfe94022 p9, a four-line cell over two
    // rows, the first of which stays on p8 with none of its lines. Where part of the cell's lines stay on the page before,
    // the cell goes on from its cut and the print has no extra line: zh-b5359de4 p10.)
    // (Only where the cell's own rule would take the whole line's room away: where it leaves some, the lines already set stand.)
    func _pg_openWholeLift(_ pgs: _PState, _ document: RichDocument, _ i: Int, _ c: _CellGeo, room: Double? = nil) -> Bool {
        guard RichTextTheme.wordWindowsPages, _pg_spansOpenWhole(pgs), Self._rowHasContinuedTopUnsaid(i, document) else { return false }
        guard let ts = document.tableStyles[c.table], ts.edges?.top ?? (ts.borders && !ts.bordersFromCells) else { return false }
        let r = room ?? _px(Self._ruleRoom(ts.edgeStyles["top"] ?? ts.borderStyle, ts.edgeWidths["top"] ?? ts.borderWidth ?? 0.5))
        return r - max(0, c.rules - c.ruleBelow) <= 0.01
    }

    func _pg_spansOpenWhole(_ pgs: _PState) -> Bool {
        let here = _pages[pgs.page]
        return !here.isEmpty && here.allSatisfy { $0.part == .text && !$0.repeated && $0.flowTop <= _tops[$0.paragraph] + 0.01 }
    }

    func _pg_ruleClosing(_ pgs: inout _PState, _ document: RichDocument, _ c: _CellGeo) -> Double {
        let own = _pg_ruleUnder(&pgs, document, c, parted: true)
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
    func _pg_cellSlacks(_ pgs: inout _PState, _ document: RichDocument, _ k: Int) -> [Double] {
        let n = _pg_cellCuts(&pgs, document, k).count
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

    func _pg_cellCuts(_ pgs: inout _PState, _ document: RichDocument, _ k: Int) -> [Double] {
        let g = geometry(k)
        // (A table nested in the cell parts between its rows, as
        // Word's does: zh-d35cbbdb's consent table, its first row
        // "項目 / 土地部分 / 合法建物部分" at page 4's foot in a cell
        // of the page-long layout table, the rest on page 5 — ours
        // took the whole table over.)
        if theme.wordRules, let image = document.paragraphs[k].image, image.textBox?.growsToFit == true,
           let inside = _textBox(image, document) {
            let top = g.textTop + (k < _imageDrop.count ? _imageDrop[k] : 0) + _px(image.textBox?.insetTop ?? 0)
            var rows = Set<Double>()
            for m in 0 ..< min(inside.document.paragraphs.count, inside.layout._cells.count) {
                if let c = inside.layout._cells[m], c.firstInRow, c.table == inside.layout._cells.compactMap({ $0 }).first?.table {
                    rows.insert(top + c.rowTop + c.ownRowHeight)
                }
            }
            // (And inside a nested row, at its cells' own line ends, as the outer rows part: Word's print of
            // sa1 03f63881 cuts the "Video-conferencia 2" table's "Consigna" row after two lines at a
            // page's foot, not at the row above.)
            let innerTable = inside.layout._cells.compactMap({ $0 }).first?.table
            let widows = (inside.document.compatibilityMode ?? 12) >= 15
            // (Only where no other cell of that inner row has a line across it: the cut stands at a line end, or
            // under the text, of every cell of the row.)
            var pieces: [_InnerPiece] = []
            for m in 0 ..< min(inside.document.paragraphs.count, inside.layout._cells.count) {
                guard let c = inside.layout._cells[m], c.table == innerTable, c.rowSpan == 1, !c.vertical,
                      inside.document.tableStyles[c.table]?.rowsCantSplit.contains(c.row) != true else { continue }
                guard m < inside.layout._painters.count, inside.layout._painters[m] != nil else { continue }
                let g2 = inside.layout.geometry(m)
                let all = Self._lineBottoms(g2.painter).map { top + g2.textTop + $0 }
                var lines = all
                if widows, inside.document.paragraphs[m].style.widowControl {
                    lines = lines.count >= 4 ? Array(lines[1 ..< lines.count - 2]) : []
                } else if !lines.isEmpty {
                    lines.removeLast()
                }
                // (A paragraph's own end is a place to part as well, where the next paragraph of the cell follows: Word's print of
                // sa1 03f63881, the "Criterios de participación" cell of bullets, keeps whole bullets of two and three lines on
                // page 14 to its foot; ours parted only inside the long ones and took the rest over, five lines short.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, let end = all.last, m + 1 < inside.document.paragraphs.count,
                   let next = inside.layout._cells[m + 1], next.table == c.table, next.row == c.row, next.column == c.column { lines.append(end) }
                pieces.append(_InnerPiece(row: c.row, column: c.column, cuts: lines, bottom: all.last ?? (top + g2.textTop)))
            }
            for piece in pieces {
                for b in piece.cuts {
                    let others = pieces.filter { $0.row == piece.row && $0.column != piece.column }
                    let columns = Set(others.map(\.column))
                    let clear = columns.allSatisfy { col in
                        let mine = others.filter { $0.column == col }
                        return mine.allSatisfy { $0.bottom <= b + 0.01 } || mine.contains { q in q.cuts.contains { abs($0 - b) < 0.5 } }
                    }
                    if clear { rows.insert(b) }
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
        // (A paragraph that keeps with the next in its cell is not a place the row may part: Word's print of
        // c2104d44 sends the empty kept paragraph that opens the chain "…, Jueves, 16 de marzo" to the next page with it,
        // and stands the line before it at the foot.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, document.paragraphs[k].style.keepNext, k + 1 < count,
           let here = _cells[k], let next = _cells[k + 1], next.table == here.table, next.row == here.row, next.column == here.column,
           document.paragraphs[k].text.allSatisfy({ $0 == " " || $0 == "\n" }) {
            // (Only an empty one: lo-89daf93d's "PSTN Calling" heading, kept with the heading under it, still stands at the foot
            // in Word's print while the heading under it and its text part to the next page.)
            return lines
        }
        return lines + [end]
    }

    // A cell merged down from a row above (Word's `w:vMerge`) is
    // one cell over the rows it covers, and its text is cut at a
    // page's foot like any cell's: when the table goes on to a new
    // page under it, what of it did not fit on the page before goes
    // on from the top of this one.
    func _pg_continueSpans(_ pgs: inout _PState, _ document: RichDocument, into i: Int, _ c: _CellGeo) {
        defer { pgs.prevPartBottom = nil }
        guard theme.wordRules, pgs.page > 0 else { return }
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
                if piece.page == pgs.page - 1, piece.part != .rules, !piece.repeated, members.contains(piece.paragraph) { found.append(n) }
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
            let footY = pgs.prevContentH - _pg_ruleUnder(&pgs, document, c, parted: true)
            let closeY = pgs.prevPartBottom.map { firstMember.verticalAlign == "center" ? min(footY, $0) : footY } ?? footY
            let limit = ref.flowTop + (min(closeY, pgs.prevY) - ref.pageY) + 0.01
            let last = members[members.count - 1]
            guard _tops[last] + _heights[last] > limit else { continue }
            var cut: Double? = nil
            for m in members {
                let cuts = _pg_cellCuts(&pgs, document, m), slacks = _pg_cellSlacks(&pgs, document, m)
                for (n, b) in cuts.enumerated() where b - (slacks.indices.contains(n) ? slacks[n] : 0) <= limit { cut = max(cut ?? b, b) }
            }
            let shownFrom = found.map { max(_allPieces[$0].flowTop, _tops[_allPieces[$0].paragraph]) }.min() ?? ref.flowTop
            let at = max(cut ?? shownFrom, shownFrom)
            for n in found {
                let old = _allPieces[n]
                let m = old.paragraph
                let top = max(_tops[m], old.flowTop), bottom = _tops[m] + _heights[m]
                guard bottom > at + 0.01, old.flowBottom > at + 0.01 else { continue }
                var fresh = PagePiece(paragraph: m, flowTop: max(top, at), flowBottom: bottom, page: pgs.page, pageY: pgs.y + max(0, top - at))
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
                _pages[pgs.page].append(fresh)
            }
        }
        // (… and stands under the table's top line there, as the row's own cells do under theirs: the row is not
        // lowered, and grows only where the cell is its tallest — see `_pg_openWholeLift`.)
        if _pg_openWholeLift(pgs, document, i, c), let ts = document.tableStyles[c.table] {
            let room = max(0, _px(Self._ruleRoom(ts.edgeStyles["top"] ?? ts.borderStyle, ts.edgeWidths["top"] ?? ts.borderWidth ?? 0.5)))
            for n in _pages[pgs.page].indices where room > 0.01 {
                let old = _pages[pgs.page][n]
                var moved = PagePiece(paragraph: old.paragraph, flowTop: old.flowTop, flowBottom: old.flowBottom, page: old.page, pageY: old.pageY + room)
                moved.repeated = old.repeated
                moved.part = old.part
                moved.inner = old.inner
                if let at = _allPieces.lastIndex(of: old) { _allPieces[at] = moved }
                _pages[pgs.page][n] = moved
            }
        }
    }

    // (A table placed against the page, down from the text above it, whose last row
    // ends past the margin does not take the page's end with it: the paragraph after
    // it is its anchor, and stands where the flow stood, over the table — zh-0b87285b's
    // title, a 29pt line at 90, over a table 126.8pt down that ends past a 451pt
    // margin, is on the table's page in Word's print; ours took it to a page of its own.)
    func _pg_tableEndsOverAnchor(_ pgs: inout _PState, _ document: RichDocument, _ c: _CellGeo, _ j: Int) -> Bool {
        theme.wordRules && RichTextTheme.wordWindowsPages && j < count && _cells[j] == nil
            && pgs.tableReturn.map { $0.table == c.table && $0.page == pgs.page && $0.y + _heights[j] <= $0.top + 0.01 } == true
    }

    func _pg_placeDeferred(_ pgs: inout _PState, _ document: RichDocument) {
        for piece in pgs.deferredUnder {
            let h = piece.flowBottom - piece.flowTop
            if pgs.y + h > pgs.contentH + 0.01, pgs.y > 0.01 { _pg_newPage(&pgs, document) }
            let again = PagePiece(paragraph: piece.paragraph, flowTop: piece.flowTop, flowBottom: piece.flowBottom, page: pgs.page, pageY: pgs.y)
            _pages[pgs.page].append(again)
            let at = _allPieces.firstIndex(where: { $0.paragraph > piece.paragraph }) ?? _allPieces.count
            _allPieces.insert(again, at: at)
            pgs.y += h
        }
        pgs.deferredUnder = []
    }
}
