// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paragraph": moved out of RichLayout.swift by test/tools/split-richlayout.py (a pure move, so that
// the parts compile side by side).

import Flutter
import FlutterSwiftBridge
import Foundation

extension RichLayout {

    /// Word for Windows at compat 14 and under honours a tab stop past the margin (lab tabpast14; sa1 0058af10, dx2 e1996ca7 and
    /// 9f798d64, xa gv-0de3e9bcf1): the text after it ends AT the stop and stays on the line. The engine fits a line against the
    /// margin, so the lines are broken by the clamped layout first (it matched Word's breaks in all four); where that is ONE line
    /// the paragraph is laid out again with room past the margin, the stops as written.
    func _layoutParagraphOnce(_ i: Int, _ p: RichParagraph, _ document: RichDocument) {
        _pastNeed[i] = nil
        _pastLeft[i] = nil
        _pastWiden = nil
        _topLift = nil
        _layoutParagraphBody(i, p, document)
        // (Word's top alignment is per line: a smaller run stands higher only on a line that holds a bigger one. The probe layout above
        // gives the line starts; the paragraph is laid out again with each line's biggest size. Only top-aligned mixed-size paragraphs.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.lineHeightPoints == nil,
           p.style.eastAsian["w:textAlignment"] == "top", p.runs.count > 1, let painter = _painters[i] {
            let named = _named(p, document)
            func sizePt(_ r: CharStyle) -> Double { r.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize }
            let u16 = Array(p.text.utf16)
            var spans: [(from: Int, to: Int, size: Double)] = []
            var at = 0
            for r in p.runs {
                defer { at += r.length }
                guard r.length > 0, r.style.script == .normal, at + r.length <= u16.count,
                      u16[at..<(at + r.length)].contains(where: { $0 != 9 }) else { continue }
                spans.append((at, at + r.length, sizePt(r.style)))
            }
            if Set(spans.map { $0.size }).count > 1 {
                let starts = _lineStarts(painter, _map(i), count: u16.count)
                var table: [(from: Int, to: Int, big: Double)] = []
                for (k, st) in starts.enumerated() {
                    let en = k + 1 < starts.count ? starts[k + 1] : u16.count
                    let sizes = spans.filter { $0.from < en && $0.to > st }.map { $0.size }
                    if let big = sizes.max(), let lo = sizes.min(), big - lo > 0.01 { table.append((st, en, big)) }
                }
                if !table.isEmpty {
                    _topLift = table
                    _layoutParagraphBody(i, p, document)
                }
            }
        }
        defer { _topLift = nil }
        guard theme.wordRules, Self._honoursStopsPastMargin(document),
              !p.style.rightToLeft, p.style.alignment == .left || p.style.alignment == .justify,
              let painter = _painters[i] else { return }
        let single = painter.computeLineMetrics().count == 1
        guard let need = (single ? _pastNeed[i] : nil) ?? _pastLeft[i], need > 0.01 else { return }
        _pastWiden = max(need, _pastNeed[i] ?? 0, _pastLeft[i] ?? 0) + _px(80)
        _layoutParagraphBody(i, p, document)
        _pastWiden = nil
        if let again = _painters[i], again.computeLineMetrics().count != 1 {
            _layoutParagraphBody(i, p, document)
        } else {
            RuleTrace.hit("word-tab-past-the-margin-keeps-its-stop-on-one-line")
        }
    }

    func _layoutParagraphBody(_ i: Int, _ p: RichParagraph, _ document: RichDocument) {
        _heldTallerLatin.remove(i)
        var p = p
        // A paragraph of hidden text alone, its mark not hidden, is one empty
        // line in its mark's look: lab hiddenline (Word for Windows) gives it
        // a full line at 10, 12 and 16pt, as a paragraph with an ordinary
        // mark and no text has — text deleted as well, once a tracked deletion
        // has gone to its balloon. (Ours set the hidden run a hair high and left
        // the line nothing: merge_hidden_redline's "Abc" paragraph.)
        if theme.wordRules, p.image == nil, p.inlineImages.isEmpty, !p.runs.isEmpty,
           p.runs.allSatisfy({ $0.style.hidden }), !_vanishes(p, document) {
            RuleTrace.hit("hidden-text-keeps-line")
            p.text = ""
            p.runs = [Run(length: 0, style: p.style.mark ?? CharStyle())]
        }
        let style = p.style
        let wordList = _wordList(p, document)
        var sides = _sideIndents(p, at: i, document)
        // `w:mirrorIndents` on a page Word mirrors: the right indent is
        // the left one and the first line's, the left the right one and
        // a hanging indent's depth (measured: `office.md`).
        // (A list paragraph's text edge is its level's, `_wordList`, and is
        // mirrored the same way: zh-bdae17c0's "․" list, left 1162 hanging
        // 425 and right 108, sets its lines 26.65pt in and ends them 36.85
        // short of the margin on its even pages in Word for Windows' print,
        // where ours kept the level's 58.1 and lost the right indent.)
        var listLeft = wordList?.left
        if _mirrored.contains(i) {
            if let wl = wordList {
                listLeft = sides.right + max(0, -wl.first)
                sides = (left: sides.left, right: wl.left + wl.first)
            } else {
                let first = firstLineIndent(p, at: i, document)
                sides = (left: sides.right + max(0, -first), right: sides.left + first)
            }
        }
        var ownLeft = listLeft.map { _px($0) } ?? _px(sides.left)
        var left = wordList != nil ? ownLeft
            : ownLeft + (style.list != nil ? _px(_listIndents(p, document)?.left ?? theme.listIndent * Double(style.listLevel + 1)) : 0)
        var right = _px(sides.right)
        // (A right-to-left paragraph's indents are its start's and its end's:
        // `w:start` (or Word's `w:left`) is the RIGHT edge, a list level's
        // as well — LibreOffice's tdf82065, "RTL with indent" under a bullet
        // of start 170.1 and hanging 56.7, ends 170.1pt short of the right
        // margin with its bullet 56.7 further in, in Word's print; ours set
        // the bullet 113 in from the left and the text against the margin.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, style.rightToLeft, !_mirrored.contains(i) {
            swap(&left, &right); if p.cell != nil { ownLeft = left }
        }
        if style.bulletAtEnd, style.list != nil { swap(&left, &right) }
        var width = _flowWidth(i)
        // On a grid of characters a body line holds whole characters of
        // Normal's size: as wide as the most of them the column takes,
        // its addition with each. zh-f0bd9ea8's 436.55pt column holds 42
        // of 10.29 (10.5, the grid -0.21), and its justified lines end at
        // 432.4 in Word's print, 4.2 short of the margin; with the
        // margin 5.1 or 10.1pt in they end at 422.1 both (lab `f0b`,
        // 2026-10-17). zh-d68ac84a's 439.4 is 30 of 14.65 exactly.
        // (Not a header's or footer's, which keep to no line grid: the
        // footer's "-1-" stands where it would without one.)
        // (Where the grid takes room away. Where it adds some, Word does
        // not round: zh-ac627439 (+0.3, 442.2pt, 40.9 cells of 10.8) sets
        // a 15pt line to 437.6.)
        // (And where it takes none: zh-18cb2079's grid of characters says
        // no charSpace, and its justified 16pt lines end at 27 cells,
        // 511.55, in a 442pt column — ours set 28 by squeezing marks.)
        // (Its cells are Normal's characters as spaced, too — twice where
        // widths are balanced: labs `cell`–`cell4` (Word for Windows,
        // zh-5be7e156's package, 16pt, Normal spaced -0.3, charSpace 0 and
        // -842, columns of 405 to 475pt): a line keeps a character only
        // while the column's whole 15.4pt cells, less its indents, hold it —
        // 28 of them in 442.25, gone at 0.25pt of indent, where cells of 16
        // left ours 1.0 more, and 1.75 and 2.25 at -842 and 465pt. A run
        // spaced otherwise than Normal is held to the same cells: 29
        // characters of 16, unspaced, need 2pt of the margin given back in
        // a 465pt column of 30.)
        var gridCut = 0.0   // what the cells' floor took off the width
        @inline(never) func _q0() {
        if theme.wordRules, p.cell == nil, _grid(i, document).pitch != nil, let add = _grid(i, document).chars, add < 0.0001 {
            let spacing = (_normalChar(document)?.letterSpacing ?? 0) * (document.balancesSpaceWidth ? 2 : 1)
            let cell = _px((_normalChar(document)?.fontSize ?? theme.fontSize) + add + spacing)
            // (Not for a paragraph of smaller characters than the cell: LibreOffice's
            // tdf149089, 9pt text on a grid of Normal's 10.5, holds 55 characters of
            // its 498.7pt column in Word's print, 495pt of them, where 47 whole cells
            // of 10.5 hold 54.)
            let base = _named(p, document)?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
            let own = _px(p.runs.map { $0.style.fontSize ?? base }.max() ?? base)
            // (Not a paragraph that says `w:snapToGrid` 0, with characters a point or more
            // larger than the cell: zh-a78d52e7's 16pt lines on Normal's 15pt cell, the column
            // cut to 435.0 of 436.5, hold the 27th character, 0.09pt over its 405.3 after the
            // indent, in Word's print.)
            let size = add > 0.0001 ? cell - _px(add) : cell
            let offGrid = RichTextTheme.wordWindowsPages && p.style.eastAsian["w:snapToGrid"] == "0" && own >= size + _px(0.9)
            // (A paragraph with half-width forms (U+FF61-FF9F) counts its line in half cells:
            // cfbf7823's line of 23 cells and a half-width ｢ holds 423pt of a 425.2pt column
            // in Word's print, where whole cells give 414.)
            let step = RichTextTheme.wordWindowsPages && p.text.unicodeScalars.contains(where: { $0.value >= 0xFF61 && $0.value <= 0xFF9F }) || !p.text.unicodeScalars.contains(where: { $0.value >= 0x2E80 && $0.value < 0xFF00 }) || ((document.compatibilityMode ?? 0) >= 14 && p.text.unicodeScalars.contains(where: { ($0.value | 0x20 >= 0x61 && $0.value | 0x20 <= 0x7A) })) ? cell / 2 : cell
            // (The cells are counted in what the indents leave: gc-p105's 453.6pt column holds 43 cells of
            // 10.5 (451.5) up to 2pt of right indent and 42 from 2.5pt, in Word's print.)
            // (Not a paragraph of larger characters than Normal's: dx2 c67f3706's 11pt lines on
            // Normal's 10.5 hold 42 characters of its 453.6pt column in Word's print, ending at
            // the margin, where 43 cells of 10.5 leave 451.5 and a character goes down.)
            // (Compat 15 and later: no cut, at any size. Labs c67lab (dx2 c67f3706's text, 11 and 16pt) and c67lab10 (10pt, below
            // Normal's 10.5), compat 14 against 15 with no charSpace, 0 and -849: the compat-14 lines stop at 43 cells of the cut
            // column, the compat-15 ones run to the margin, at all three sizes. The cut documents above are compat 12, 14 or none.)
            let fullWidth = (document.compatibilityMode ?? 0) >= 15
            // (Compat 14 also cuts smaller characters: c67lab10's 10pt lines on Normal's 10.5 cell, no charSpace, hold 45 or 46
            // characters in Word's print, 45 cells of 10pt less than the margin's 45.4; compat 15 holds 46 or 47.)
            // (Not a paragraph that says `w:snapToGrid` 0: zh-e68a2f57's 10.5pt note lines on a 16pt Normal cell, compat 14, run to the margin in Word's print.)
            let smallerCut = (document.compatibilityMode ?? 0) == 14 && p.style.eastAsian["w:snapToGrid"] != "0"
            if cell > 0, own >= size - _px(0.01) || smallerCut, !offGrid, !fullWidth {
                let room = width - left - right
                let cut = min(room, ((room + _px(0.01)) / step).rounded(.down) * step)
                gridCut = room - cut; width -= gridCut
            }
        }
        }
        _q0()
        // A floating frame: as wide as it says, from where it says.
        var frameLeft: Double? = nil
        @inline(never) func _q1() {
        if floatsFrames, theme.wordRules, p.cell == nil, let frame = style.frame {
            let marginLeft = _px(frameMargins.left), marginRight = _px(frameMargins.right)
            // The band the frame is placed in, from the text's left edge.
            let band: (left: Double, width: Double) = frame.horizontalAnchor == "page"
                ? (-marginLeft, width + marginLeft + marginRight) : (0, width)
            let own = frame.width.map(_px) ?? band.width
            // ("Outside" the page's outer edge, as for a floating shape:
            // zh-c2f6d17a's footer frame, aligned outside, has its page
            // number left on the even pages in Word's print, with no
            // even-and-odd headers set.)
            let outside = leftHandPage ? "left" : "right", inside = leftHandPage ? "right" : "left"
            let hAlign = frame.horizontalAlign == "outside" ? outside : frame.horizontalAlign == "inside" ? inside : frame.horizontalAlign
            switch hAlign {
            case "center": frameLeft = band.left + (band.width - own) / 2
            case "right": frameLeft = band.left + band.width - own
            case "left": frameLeft = band.left
            default: frameLeft = band.left + _px(frame.x)
            }
            width = own
            left += frameLeft!
        }
        }
        _q1()
        // (A frame on the page in the body is as wide as it says: the
        // 482pt title frame of zh-90e0cea8's cover holds its 18-character
        // title on one line, where the 420pt column parted it.)
        // (A frame set in the text, with no text beside it, is as wide as it
        // says, centred on the page where it says that: tdf105035_framePrB's
        // IEEE title, w 9360 over the style's page anchor and xAlign
        // centre, is 468pt wide and parts "…TRANSACTIONS | and JOURNALS" in
        // Word's print, where ours set it across the 518pt column.)
        let notBesideInText = style.frame?.verticalAnchor == "text" && (style.frameXML ?? "").containsSubstring("w:wrap=\"notBeside\"")
        if frameLeft == nil, theme.wordRules, p.cell == nil, let frame = style.frame, let w = frame.width,
           Self._framePlaced(frame), Self._onThePage(style) || notBesideInText {
            let column = width
            width = _px(w) + left
            // (Centred between the margins where its chain says so and
            // gives no x: the cover's "山东省市场监督管理局 发布", a 372pt
            // frame, stands in the middle of the column in Word's print.)
            if frame.horizontalAnchor == "margin", frame.horizontalAlign == "center", !(style.frameXML ?? "").containsSubstring("w:x=\""),
               column - width > 0.5 {
                let shift = (column - width) / 2
                left += shift
                width += shift
            }
            // (At its x on the page: the cover's "实施" date stands at the
            // right in its own 200pt frame.)
            // (An x the style chain states wins over an alignment from
            // further down it: the date's own style puts it at 354pt, its
            // parent's says right, and Word's print has it at 354.)
            if notBesideInText || Self._stripFrame(style), frame.horizontalAnchor == "page", frame.horizontalAlign == "center",
               !(style.frameXML ?? "").containsSubstring("w:x=\"") {
                let setup = _setup(ofParagraph: i)
                let shift = _px((setup.width - w) / 2 - setup.marginLeft - setup.gutter)
                left += shift
                width += shift
            } else if frame.horizontalAnchor == "page", frame.horizontalAlign == nil || (style.frameXML ?? "").containsSubstring("w:x=\"") {
                let setup = _setup(ofParagraph: i)
                let shift = _px(frame.x - setup.marginLeft - setup.gutter)
                left += shift
                width += shift
            }
        }
        // (A frame on the page with an x and no width runs from that x to the right margin:
        // lo-af81b53e's centred small-caps frame, x 1675 over a 567 gutter, stands in
        // [83.75, 517.15] in Word's print, centred on 300.45, where ours took the whole column.)
        if frameLeft == nil, theme.wordRules, p.cell == nil, let frame = style.frame, frame.width == nil,
           frame.horizontalAnchor == "page", frame.verticalAnchor == "page", frame.horizontalAlign == nil,
           (style.frameXML ?? "").containsSubstring("w:x=\"") {
            let setup = _setup(ofParagraph: i)
            left += _px(frame.x - setup.marginLeft - setup.gutter - 0.32)
            // (Narrower than Word's ink, 433.1pt: glyph and space advances now agree with Word's to 0.05pt and a line's ink ends
            // within 0.3pt of it, but with the box at Word's width ours still takes "NULLA" onto the fourth line, so
            // something in the fit test, not the widths, is a hair apart.)
            width -= _px(10.0)
        }
        if let w = _pastWiden { right -= w }
        var textWidth = max(1, width - left - right + (frameLeft ?? 0))
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.cell == nil, let room = style.wrapperRoom, _px(room) > width { textWidth += _px(room) - width }
        // (Centred or set right, a numbered line is set across its
        // hanging indent too: zh-3c055c9b's caption "表1　古佳川不實核銷表
        // (…財物)", 表標題 centred on a 24pt hang, is one line in Word's
        // print centred on the indent's edge, 465.8pt in a column of
        // 450.85 and the hang; ours took no more than the column, and
        // "物)" went over the page with the table under it.)
        if theme.wordRules, p.cell == nil, let wl = wordList, wl.first < 0,
           style.alignment == .center || style.alignment == .right {
            left += _px(wl.first)
            textWidth -= _px(wl.first)
        }
        @inline(never) func _blk0() {
        if let c = p.cell {
            let widths = _columnWidths[c.table] ?? []
            let colWidth = c.column < widths.count
                ? widths[c.column ..< min(widths.count, c.column + c.span)].reduce(0, +) : width
            let colLeft = _tableLeft(c.table, document) + widths.prefix(c.column).reduce(0, +)
            let ins = _cellInsets(c.table, document)
            var pad = c.padding.map { EdgeInsets(left: _px($0.left), top: _px($0.top), right: _px($0.right), bottom: _px($0.bottom)) }
                ?? EdgeInsets(left: ins.left, top: ins.top, right: ins.right, bottom: ins.bottom)
            // (A cell merged down into the row sets it deeper: `CellRef.rowMarginTop`.)
            if theme.wordRules, c.rowMarginTop != nil || c.rowMarginBottom != nil {
                pad = EdgeInsets(left: pad.left, top: max(pad.top, _px(c.rowMarginTop ?? 0)), right: pad.right,
                                 bottom: max(pad.bottom, _px(c.rowMarginBottom ?? 0)))
            }
            // The text keeps clear of the cell's own side lines: its left
            // edge stands the margin and half the line's width in, and
            // never inside the line; its right inset is the margin less
            // half the line. Lab `cb3` in bug65649's package (Word 16,
            // 2026-10-15): at a 108-twip margin the text of a 1pt-lined
            // cell starts 0.48pt further in than an unlined one's, of a
            // 3pt line 1.44, of 12pt 6.48; at 28 twips a 6pt line sets
            // it 6pt in, the margin lost under it; and a right-aligned
            // "H" in the cell beside ends half a point nearer the edge
            // per point of line. With no margin the text loses the whole
            // line: the estimate tables' "зарплаты" in a 1060-twip cell
            // under 85-twip indents wraps "зарплат" / "ы" from a 1.5pt
            // line on and not under a 1pt one (lab `cb`), as Word's
            // bug65649 print has it from page 22.
            // (Applied below, where the cell's lines are resolved.)
            // A ruled row is its rule taller, as Word sets it: the line
            // above each row takes its width from the row, and the last
            // row has the table's bottom line too.
            // (The cell's own side over the table's: a table ruled
            // around its rim alone whose cells each rule their four
            // sides has a line above every row. And a double line is
            // three of its width — two lines and the gap: rows 17.5pt
            // apart at half a point, 20.5 at one and a half, where a
            // single line's are 16.5 and 17.5.)
            // (The line between two rows is the upper row's bottom
            // one as much as the lower row's top one: a form whose
            // cells rule their bottoms and say none above is ruled
            // between every two rows, 31pt apart for rows 30 high.)
            var rules = 0.0
            var cellRightRule = 0.0
            var ruleBelow = 0.0
            var ownTopRule = 0.0
            var ruleNext = 0.0
            // (A table with no style of its own — one made in the editor
            // — is ruled like one whose file says nothing more than
            // that it is ruled.)
            if theme.wordRules {
                let ts = document.tableStyles[c.table] ?? TableStyle()
                let rows = _tableRows[c.table] ?? 0
                // A left or right side the cell's borders do not name is
                // as wide as the table's line there or the cell's own,
                // whichever is wider; a top or bottom one is the table's.
                // zh-701eda18's form ends on a row whose tallest cell
                // states a 0.5pt double on its right alone, and Word gives
                // the table's 3pt thickThinSmallGap bottom its whole 4.3pt
                // under it, where the cell's 0.5 left 2 and all after stood
                // 2.5 high. (A cell's thick side line is no room above or
                // below it: lab `cal` in zh-5251dd23's package (Word 16,
                // 2026-10-18), its calendar's rows of two 17pt lines, a
                // 2.25pt line on the first cell's left and the last one's
                // right, are 34.8pt — and 34.56 with no stated height,
                // the line on either side, the cell the tallest or not —
                // where ours stood 36.6. zh-cec9d337's rows, which this
                // once explained, were its "○" lines short of the grid.)
                func sideWidth(_ d: CellRef, _ tableSide: String) -> Double {
                    let table = ts.edgeWidths[tableSide] ?? ts.borderWidth ?? 0.5
                    return max(d.borderWidth ?? table, table)
                }
                func rule(_ d: CellRef, _ side: String) -> Double {
                    let said = Self._cellSide(d.bordersXML, side) ?? Self._cellSide(d.rowBordersXML, side)
                    let end = d.row + d.rowSpan - 1
                    let tables = side == "top" ? (d.row == 0 ? ts.edges?.top : ts.edges?.insideH) : (end >= rows ? ts.edges?.bottom : ts.edges?.insideH)
                    // (Where the cells rule the table, a side none of them
                    // states is not ruled: the table and its style say
                    // nothing, and Word draws nothing — zh-a0e932c2's
                    // rows ruled only under every second one, and a
                    // last column of no borders at all.)
                    guard (side == "top" ? d.edges?.top : d.edges?.bottom) ?? tables ?? (ts.borders && !ts.bordersFromCells) else { return 0 }
                    let tableSide = (side == "top" ? d.row > 0 : end < rows) ? "insideH" : side
                    let style = said?.style ?? ts.edgeStyles[tableSide] ?? ts.borderStyle
                    let width = said?.width ?? (ts.edgeWidths[tableSide] ?? ts.borderWidth ?? 0.5)
                    var room = Self._ruleRoom(style, width)
                    // (A rule the cell states with an explicit w:sz="0" is a
                    // hairline Word draws without growing the row: dx2
                    // 33a4668e's rows are 0.25 pt shorter than ours.)
                    if said != nil, theme.wordRules, Self._cellSideZero(d.bordersXML, side) ?? Self._cellSideZero(d.rowBordersXML, side) ?? false { RuleTrace.hit("word-cell-side-border-size-zero-adds-no-row-room"); return 0 }
                    // (At the table's own edge the wider of its line and the
                    // cell's wins: zh-cb56e605's outset top over a cell's
                    // single 0.5 — Word's header stands 0.8 lower.)
                    if said != nil, tableSide == side, theme.wordRules, ts.cellSpacing != nil {
                        room = max(room, Self._ruleRoom(ts.edgeStyles[side] ?? ts.borderStyle, ts.edgeWidths[side] ?? ts.borderWidth ?? 0.5))
                    }
                    return _px(room)
                }
                // The cell's left and right lines, resolved as its top and
                // bottom ones are: the cell's own side over the table's,
                // which rules a side column by its own edge and the rest
                // by its inside one.
                func sideLine(_ d: CellRef, _ side: String) -> Double {
                    let said = Self._cellSide(d.bordersXML, side) ?? Self._cellSide(d.rowBordersXML, side)
                    let atEdge = side == "left" ? d.column == 0 : d.column + d.span >= widths.count
                    let tables = atEdge ? (side == "left" ? ts.edges?.left : ts.edges?.right) : ts.edges?.insideV
                    guard (side == "left" ? d.edges?.left : d.edges?.right) ?? tables ?? (ts.borders && !ts.bordersFromCells) else { return 0 }
                    let tableSide = atEdge ? side : "insideV"
                    let style = said?.style ?? ts.edgeStyles[tableSide] ?? ts.borderStyle
                    let width = said?.width ?? sideWidth(d, tableSide)
                    return _px(Self._ruleRoom(style, width))
                }
                // (Separated where the row has the table's cell spacing:
                // one that states none of its own collapses — see
                // `rowsUnspaced`.)
                func spaced(_ row: Int) -> Bool { ts.cellSpacing != nil && !(theme.wordRules && ts.rowsUnspaced.contains(row)) }
                var l = sideLine(c, "left"), r = sideLine(c, "right")
                // (A side the cell leaves bare that its neighbour rules is
                // ruled all the same: the line stands on the edge they
                // share. zh-37b6536f's count cells say nil on the left
                // under a 1pt line from the cell before, and Word sets
                // "尚未审结" a character a line in their 30pt, where ours,
                // counting no line there, took two.)
                func neighbour(_ before: Bool) -> CellRef? {
                    var k = before ? i - 1 : i + 1
                    while k >= 0, k < count, let d = document.paragraphs[k].cell, d.table == c.table {
                        if d.row <= c.row, d.row + d.rowSpan - 1 >= c.row,
                           before ? d.column + d.span == c.column : d.column == c.column + c.span { return d }
                        k += before ? -1 : 1
                    }
                    return nil
                }
                // (Not where the cells stand separated, even by none: there the neighbour's line lies in
                // the neighbour's box. zh-147bdae0's p14 table, tblCellSpacing 0, 0-twip left margins
                // beside a 1pt line, starts "1.建置…" at the line's inner edge in Word's print, where ours,
                // a whole line further in, left "系" for the next line.)
                if l == 0, c.column > 0, !spaced(c.row), let d = neighbour(true) { l = sideLine(d, "right") }
                if r == 0, c.column + c.span < widths.count, !spaced(c.row), let d = neighbour(false) { r = sideLine(d, "left") }
                cellRightRule = r
                if l > 0 || r > 0 {
                    if spaced(c.row) {
                        // (Separated, each cell's lines lie inside its own
                        // box, both of them: bib-chernigovka's 51pt year
                        // column of outset lines holds "90 лет" on one line
                        // in ours and on two in Word's print.)
                        pad = EdgeInsets(left: pad.left + l, top: pad.top, right: pad.right + r, bottom: pad.bottom)
                    } else {
                        // (From 2013's layout on: before it the text keeps its
                        // margin whatever the line — lab `cb` (Word 16,
                        // zh-e029cf49's package, mode 14, 108-twip margins):
                        // "AAAA" starts 76.56 in cells ruled 0.5, 1 and 3pt
                        // alike, where mode 15 sets it 82.08, 82.56, 83.52;
                        // ours stood a quarter point in at 0.5.)
                        // (And on the right never under the line: zh-8628cfbe's
                        // last column, 1.4pt margins inside a 2.25pt right line,
                        // ends its text 1.26 short of the line's middle in Word's
                        // print — ours, its margin less half the line, 0.275, set
                        // "…相同者得基準分" on a line Word wraps before "分". A
                        // cell of no margin keeps none: zh-15ecc2c6's outset
                        // lines over 0-twip margins have their text to the line.)
                        // (Never inside the line holds at the table's edge,
                        // where the line is drawn inward. Between two inside
                        // lines a cell of no margin keeps half of each clear:
                        // zh-5bfac68f's 0-margin cells start 0.24 past a 0.5pt
                        // line's middle in Word's print, where ours stood a
                        // whole line in, and bug65649's estimate cells lose
                        // the halves of both. With the table's edge on the
                        // left the right line takes nothing still
                        // (zh-e51c31a7's "未來運用規劃", one line in Word's
                        // print), and with none on the right the left half is
                        // all: zh-b8de3ae2 p14's last cell holds "其他收入",
                        // 24pt in 24.4 between its indents, two a line, where
                        // ours, a whole line in, set one.)
                        let modern = (document.compatibilityMode ?? 12) >= 15
                        let inside = c.column > 0, insideRight = inside && c.column + c.span < widths.count
                        // (In Word for Windows and for Mac the lines take nothing from the
                        // text's margin: it keeps the margin, or half the line
                        // where that is more, from each line's middle. Lab ci
                        // (zh-8628cfbe's table, mode 15, 28-twip margins): the
                        // text of every column starts 1.32-1.44 past the line
                        // on its left and ends 1.44 short of the one on its
                        // right, under 0.5 and 1.5pt lines, the table's or the
                        // cells' own alike, and 1.50 under 3pt ones; ours stood
                        // half the left line further in and half the right one
                        // nearer, 0.37pt wider in p13's cell, which took a "，"
                        // Word sends down. Mac Word's lab cimac (macOS-doc, three
                        // 120pt cells, 5.4 margins, lines 0.5 to 3pt) agrees. The table's left line stands inside
                        // it, `_edgeShift`, its first column's text where it was.)
                        // (A rule of a later row's first cell, the first row stating none, moves neither the table's edge
                        // nor that row's text: sa1 f84c295b's sixth row, a double left rule, starts its text at the margin
                        // and the cell margin, 74.40, in Word's print, where ours stood 1.07 in.)
                        let laterRowRule = c.column == 0 && c.row > 0 && _tableOwnLeft[c.table] == nil
                        let shift = laterRowRule ? l / 2 : _edgeShift(c.table, document)
                        let half = RichTextTheme.wordWindowsPages && document.compatibilityMode == 14   // (lab tbl14 is mode 14; mode 12 keeps the whole line)
                        if modern, shift > 0 || inside {
                            pad = EdgeInsets(left: max(pad.left, l / 2) + (inside ? 0 : max(0, l / 2 - shift)), top: pad.top,
                                             right: max(pad.right, r / 2), bottom: pad.bottom)
                        } else {
                        pad = modern
                            ? EdgeInsets(left: inside ? pad.left + l / 2 : max(pad.left + l / 2, l), top: pad.top,
                                         right: insideRight ? max(pad.right - r / 2, r / 2) : max(pad.right - r / 2, min(pad.right, r / 2)), bottom: pad.bottom)
                            : (pad.left == 0 && !half && l > 0
                                // (Zero-margin cell in mode 12: Word's text stands at the margin, the wrap width the same as with the line's room taken; shifted, not widened.)
                                ? EdgeInsets(left: 0, top: pad.top, right: pad.right + l, bottom: pad.bottom)
                                : EdgeInsets(left: max(pad.left, half ? l / 2 : l), top: pad.top, right: half && (c.padding == nil || (pad.right == 0 && pad.left == 0)) ? max(pad.right, r / 2) : pad.right, bottom: pad.bottom))
                        }
                    }
                }
                var below = 0.0
                var top = rule(c, "top")
                // (Collapsed, a row's text stands under its thickest top
                // line, whichever cell states it: zh-147bdae0's repeated
                // header row rules its last cell's top 1.5pt and the rest
                // 0.5, and every cell's text is 1pt lower in Word's print
                // than under its own line — 序 at 109.4, ours 108.2.)
                if theme.wordRules, !spaced(c.row) {
                    var k = i - 1
                    while k >= 0, let d = document.paragraphs[k].cell, d.table == c.table, d.row == c.row { top = max(top, rule(d, "top")); k -= 1 }
                    k = i + 1
                    while k < count, let d = document.paragraphs[k].cell, d.table == c.table, d.row == c.row { top = max(top, rule(d, "top")); k += 1 }
                }
                // (The row above's bottom line, where this cell says none
                // of its own, lies in this cell's top margin: room only
                // for what of it the margin does not hold. Lab `bm` in
                // table-indent's package, Word 16, 2026-10-15: under a 1pt
                // line rows of 18.4pt text are 19.4 apart with no margins,
                // 21.1 with 55 twips above, 22.1 with them below, 19.9 at
                // 10 twips each — and 20.4 there where every cell rules its
                // own top. table-indent's cells rule their bottoms alone,
                // and its rows stood 0.5pt apart too far.)
                // (Not in a table of separated borders, where the row above
                // keeps its line in its own box: zh-147bdae0's commitment
                // tables (cell spacing 0, each cell's top nil, its bottom
                // 1pt, no margin above) step 23.8pt a one-line row in
                // Word's print, ours 24.8, the line taken twice.)
                if c.row > 0, !(theme.wordRules && (spaced(c.row) || spaced(c.row - 1))) {
                    var k = i - 1
                    while k >= 0, let d = document.paragraphs[k].cell, d.table == c.table, d.row + d.rowSpan - 1 >= c.row - 1 {
                        if d.row + d.rowSpan - 1 == c.row - 1 { top = max(top, rule(d, "bottom") - pad.top) }
                        k -= 1
                    }
                    // (A cell merged on through the line takes room for
                    // the bottom its part above the line states, though
                    // none is drawn inside the merge: zh-701eda18's form
                    // merges "單位申請" over four exact rows, each part
                    // stating a 3pt thickThinSmallGap bottom, and Word
                    // centres every row's text under it 1.9pt lower —
                    // lab `l701`, the line gone from the cell, puts it
                    // back where ours stood.)
                    for k in _tableMerged[c.table] ?? [] {
                        guard let d = document.paragraphs[k].cell, d.row < c.row, d.row + d.rowSpan - 1 >= c.row else { continue }
                        let part = c.row - 1 - d.row
                        let xml = part == 0 ? d.bordersXML : part - 1 < d.continuationBordersXML.count ? d.continuationBordersXML[part - 1] : nil
                        if let side = Self._cellSide(xml, "bottom") { top = max(top, _px(Self._ruleRoom(side.style, side.width)) - pad.top) }
                    }
                }
                // (Separated, the table's own top and bottom lines frame
                // it outside its cells, ruled or not: bug57031's SAS tables
                // (cell spacing 0, every cell's sides nil, the table's top
                // line 0.75pt and bottom 0.25) are framed in Word's print
                // and each stands that much taller; ours took no room for
                // either, and page 11 ran 2.7pt short by its foot.)
                func frame(_ side: String) -> Double {
                    // (A table ruled only through its cells' own lines, none at
                    // the table level, stands no frame of its own: 3d6b9b5d's.)
                    guard theme.wordRules, spaced(c.row),
                          (side == "top" ? c.edges?.top : c.edges?.bottom) == false || !ts.bordersFromCells,
                          (side == "top" ? ts.edges?.top : ts.edges?.bottom) ?? ts.borders else { return 0 }
                    let style = ts.edgeStyles[side] ?? ts.borderStyle
                    let width = ts.edgeWidths[side] ?? ts.borderWidth ?? 0.5
                    return _px(Self._ruleRoom(style, width))
                }
                if c.row == 0 { top += frame("top") }
                if top > 0 { pad = EdgeInsets(left: pad.left, top: pad.top + top, right: pad.right, bottom: pad.bottom) }
                rules = top
                ownTopRule = rule(c, "top")
                // (A table that states its cell spacing — even none, as
                // every HTML-converted table does — rules each cell on
                // its own, the way the web's separated borders do: a
                // row has its own bottom line under its own top one,
                // and stands a line taller than a collapsed table's. Lab
                // `ob2` in bug59058's package, Word 16, 2026-10-15:
                // rows of 12pt text under 75-twip margins, no lines
                // 23.36pt apart, 0.75pt lines 24.88 — single or outset
                // alike — where a table of no cell spacing gains the one
                // line. bug59058's state list had a row more a page.)
                let separated = theme.wordRules && (spaced(c.row) || spaced(c.row + c.rowSpan))
                if c.row + c.rowSpan - 1 >= rows || separated {
                    let bottom = rule(c, "bottom") + (c.row + c.rowSpan - 1 >= rows ? frame("bottom") : 0)
                    if bottom > 0 { pad = EdgeInsets(left: pad.left, top: pad.top, right: pad.right, bottom: pad.bottom + bottom) }
                    rules += bottom
                    below = bottom
                }
                ruleBelow = below
                // The line under the row where it ends a page — the next
                // row's top one, or its own bottom one — which Word gives
                // room to before it sets the row there: bug65649's
                // estimate tables pair a 24.65pt row with a 13.85pt unit
                // row under it, ruled only above each pair, and the last
                // unit row on page 26 (0.6pt of room left, its line 0.75)
                // opens Word's page 27; ours had set it at the foot.
                if c.row + c.rowSpan - 1 < rows {
                    ruleNext = rule(c, "bottom")
                    var k = i + 1
                    while k < count, let d = document.paragraphs[k].cell, d.table == c.table, d.row <= c.row + c.rowSpan {
                        if d.row == c.row + c.rowSpan { ruleNext = max(ruleNext, rule(d, "top")) }
                        k += 1
                    }
                }
                // Cell spacing (`w:tblCellSpacing`): s round every cell's
                // text and s more at the table's edges — Word for Windows,
                // lab `cs` (one-line rows at s of 0, 0.75 and 5pt): each
                // row 2s taller, the first row's text 2s down and the table
                // 2s longer under its last, the first column's text 2s and
                // the others' s further right. zh-9c5d0c3f's road signs
                // gained 1.5pt a row on ours.
                if let spacing = ts.cellSpacing, spacing > 0 {
                    let sp = _px(spacing)
                    let lastColumn = c.column + c.span >= widths.count
                    pad = EdgeInsets(left: pad.left + sp + (c.column == 0 ? sp : 0),
                                     top: pad.top + sp + (c.row == 0 ? sp : 0),
                                     right: pad.right + sp + (lastColumn ? sp : 0),
                                     bottom: pad.bottom + sp + (c.row + c.rowSpan - 1 >= rows ? sp : 0))
                }
            }
            // (A cell with a table floating in it, against the text, stands
            // at the cell's top whatever its vertical alignment — Word for
            // Windows on LibreOffice's floattable-leak: the nested tables
            // at the top of a centred cell, the anchor paragraph unmeasured.)
            var cellAlign = c.verticalAlign
            if cellAlign == "center" || cellAlign == "bottom", theme.wordRules, RichTextTheme.wordWindowsPages, c.rowSpan == 1 {
                var k = i
                while k < count, let d = document.paragraphs[k].cell, d.table == c.table, d.row == c.row, d.column == c.column {
                    if let image = document.paragraphs[k].image, image.name == "table", let f = image.float, f.againstText {
                        RuleTrace.hit("cell-with-nested-floating-table-is-top-aligned")
                        cellAlign = nil
                        break
                    }
                    k += 1
                }
            }
            _cells[i] = _CellGeo(table: c.table, row: c.row, column: c.column,
                                 colLeft: colLeft, colWidth: colWidth, span: c.span, rowSpan: c.rowSpan, edges: c.edges,
                                 verticalAlign: cellAlign, direction: c.textDirection, pad: pad, rules: rules, ruleBelow: ruleBelow, borders: c.borders)
            _cells[i]!.ruleNext = ruleNext
            _cells[i]!.margin = c.padding.map { _px($0.bottom) } ?? 0
            _cells[i]!.tableMarginLeft = document.tableStyles[c.table]?.tableOwnMarginLeft.map { _px($0) }
            _cells[i]!.ownTopRule = ownTopRule
            left = colLeft + pad.left + ownLeft
            textWidth = max(1, colWidth - pad.left - pad.right - ownLeft - right)
            // (A negative right indent lets the text run past the cell's right line, but not far: Word keeps it
            // within 1.4pt of the cell's outer edge less half the right line (the whole line in a cell with no
            // margin). Lab cellrind3 (Word for Windows, mode 15, 5000-5085 twips, right indent -400, 18 cells in
            // each of six tables): the last "i" of the first line stands at most 1.41, 1.16, 0.63 and 0.17pt past the
            // edge under no line and 0.5, 1.5 and 3pt lines with 108-twip margins, and 0.81 and -1.49 under 0.5 and
            // 3pt lines with none, where ours ran the whole 20pt. The lab held Latin text only: a full-width "）" ends 1.9pt past the edge in zh-ae2dd08d's cells and a drawing's anchor line is not text, so the cap is for Latin text. It bounds where left-aligned text may run, not where a CENTRED line sits: sa1 c2104d44's centred cell lines (right indent -279 in a 9953-twip cell) stand 6.98pt right of the unindented centre in Word's print, half the whole indent, ours 3.3pt with the cap, so a centred paragraph keeps the whole width.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, (document.compatibilityMode ?? 12) >= 15, right < 0, style.alignment != .center, document.tableStyles[c.table]?.cellSpacing == nil, document.tableStyles[c.table]?.fixedLayout == true, document.tableStyles[c.table]?.hasPctCells != true,
               !p.text.isEmpty, !p.text.unicodeScalars.contains(where: { Self._isEastAsianScalar($0.value) || $0.value == 0xFFFC }) {
                let limit = colWidth + _px(1.4) - (pad.right == 0 && c.padding != nil ? cellRightRule : cellRightRule / 2) - left + colLeft
                if limit < textWidth, limit >= 1 {
                    RuleTrace.hit("cell-negative-right-indent-stops-at-the-cell-edge")
                    textWidth = limit
                }
            }
            // (Across its hanging indent, as in the body — see above: a
            // centred "□" item in a cell of zh-20c1d74a's p46 form,
            // "□回收地址" in a 63.4pt cell on a 12pt hang, is one line
            // from the cell's text edge in Word's print; ours kept the
            // hang and set "址" on a line of its own.)
            if theme.wordRules, let wl = wordList, wl.first < 0, style.alignment == .center || style.alignment == .right {
                left += _px(wl.first)
                textWidth -= _px(wl.first)
            }
            // (A cell that does not wrap (`w:noWrap`) keeps its text on
            // its line, over its spacing if it must: zh-045c5a75's
            // "第 15-1 條" is whole in Word's print, in a column its widest
            // such text sizes — `_pctColumns`.)
            if theme.wordRules, c.span == 1, document.tableStyles[c.table]?.noWrapColumns.contains(c.column) == true {
                textWidth = max(textWidth, _maxContent(i, p, document) + 1)
            }
            // (A cell whose text is one fitted group (`w:fitText`) keeps it on its line when the group is a hair wider than the cell:
            // 9ba34429's "1学年", 18pt in 17.95pt, one line in Word's print.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, let fit = Self._fitTextOverflow(p), fit.groupPoints > 0 {
                let want = _px(fit.groupPoints)
                if want > textWidth, want - textWidth < _px(8) { textWidth = want + _px(2.5) }
            }
            if c.textDirection != .horizontal {
                // Turned text runs along the row's height, which the row's
                // other cells decide: laid out provisionally at the rows'
                // own heights, and again at the placed height in
                // `_placeBlocks`.
                let heights = document.tableStyles[c.table]?.rowHeights ?? [:]
                let own = (c.row ..< c.row + c.rowSpan).reduce(0.0) { $0 + (heights[$1] ?? 0) }
                textWidth = own > 0 ? max(1, _px(own) - pad.top - pad.bottom - ownLeft - right) : 100_000
            }
        } else {
            _cells[i] = nil
        }
        }
        _blk0()
        // The box before the text: the first line's indent, or — for a
        // list as Word sets it — from the number at the first line's
        // offset to where the text starts: at the number's end, a space
        // after it, or the next tab stop (the text's own left, when the
        // number fits in the hanging indent).
        var lead = _px(firstLineIndent(p, at: i, document))
        _boxFirstLineShift[i] = 0
        // (Beside a table floating by the text that stands at the margin: the
        // first line is held in past it, as Word sets text in the strip a
        // narrow floating table leaves. LibreOffice's n775899, a one-row
        // table of 283pt with "This is some text" after it, has that line at
        // x 359.5 on the table's own line in Word's print.)
        _besideLead[i] = 0
        _besideRightSide[i] = false
        if let beside = _besideIndent(i, p, document) {
            if beside.right {
                // (A table at the right: the lines end short of it, the first line starts where it would.)
                _besideLead[i] = beside.indent
                _besideRightSide[i] = true
            } else if beside.indent > lead {
                lead = beside.indent
                _besideLead[i] = beside.indent
            }
        }
        if theme.wordRules, _fixedTextFrame != nil, p.cell == nil, style.list == nil,
           !style.rightToLeft, style.alignment == .left || style.alignment == .justify, lead > 0,
           !p.text.utf16.contains(0x09), _named(p, document)?.char.horizontalScale == nil,
           !p.runs.contains(where: { $0.style.horizontalScale != nil || $0.style.ruby != nil }),
           let ch = p.text.first, !ch.isWhitespace, ch != "\u{FFFC}", let run = p.runs.first {
            // Measure with the same resolved faces and Word advances as
            // the paragraph. A placeholder alone must not occupy line one:
            // Word prints its first glyph there even when it overflows.
            let first = RichParagraph(text: String(ch), charStyle: run.style, style: p.style)
            let span = _span(for: first, at: nil, document, textWidth: 100_000).0
            let probe = TextPainter(text: span, textDirection: .ltr)
            probe.layout(maxWidth: 100_000)
            let advance = probe.width
            probe.dispose()
            if lead + advance > textWidth + 0.01 {
                let fitted = max(0, textWidth - advance - _px(0.01))
                _boxFirstLineShift[i] = lead - fitted
                lead = fitted
            }
        }
        // (A first line indented past the margin holds the first character
        // all the same, the rest from the second line. Lab `ind` (Word 16,
        // zh-9e020c95's package): "隆阳区…" at 5472 twips and a 6400-twip
        // first line, right- or left-aligned, sets "隆" on the first line,
        // off the page, and the rest on the next. The engine would keep the
        // box alone on the first, so it stops an em short of the margin:
        // the character is on its line, if not as far over as Word's.)
        @inline(never) func _blk1() {
        @inline(never) func _q2() {
        if theme.wordRules, lead > textWidth, !p.text.isEmpty {
            // (In a cell, a first line indented to the cell's
            // whole width or past it — its margins and the paragraph's side
            // indents in it — shows
            // nothing: Word leaves that line's word out and sets the rest
            // from the second line. Lab `ovi2` (Word for Windows,
            // zh-9bcea239's score cell, 19.45pt, margins 0): a 15pt first
            // line draws its "5" past the cell, 20pt and on draw nothing;
            // `ovi`: in a 40pt column at 5.4pt margins 31.6pt draws, 60 does
            // not, and "5 abc def" loses only the "5"; zh-08e95de4's 31.2pt in
            // a 33.75pt cell, 22.95 of text, draws no "基" — lab `ci` (windows, 95.7 text
            // left): the glyph stands at the indent less 0.3, drawn to 24pt (119.4) and gone
            // from 28 (123.4 against the border at 123.5), the line still taking its 15pt,
            // so the edge is the cell's right border, not the cell's width from the text's
            // left as this once read. zh-9bcea239's scores
            // (31.6pt in 19.45) are in no line of Word's print.
            // Word for Windows only: Word for Mac's print of zh-9bcea239
            // keeps lines that this leaves out, 95.9 -> 94.7 with it.)
            if RichTextTheme.wordWindowsPages, p.cell != nil, let c = _cells[i], lead >= textWidth + ownLeft + right + c.pad.right - _px(0.35) {
                // (An East Asian first character is a line of its own that draws nothing —
                // lab `ci`: nine 15pt lines, the first blank — so it stays as a space of
                // its width, not taken out: zh-08e95de4's "基基本分值…".)
                // (Word's print still carries the glyph, clipped by the cell, at the
                // indent: 94.0 in zh-08e95de4's p2, 68.1 + 31.2 - 5.4 less the cell's margin.)
                if let f = p.text.utf16.first, f >= 0x2E80 { p = Self._hidingFirstWord(p, unseenCharacter: true) }
                else { p = Self._hidingFirstWord(p, keeping: true) }
            }
            // (In a text box the same, from the box's width less its left
            // inset: lab `tbi` (`windows`, zh-b24b396a's package, each a fresh
            // Word for Windows print) — a 23.5pt box at insets 7.2 draws a
            // first line's "A" at its indent, past the box, to 15pt and none
            // from 18 (edge 16.3); at insets 0 to 21, none at 30 (edge 23.5);
            // "A abc def" in a 60pt box loses only its "A" at 60 (edge 52.8),
            // grouped or not. zh-b24b396a's Text Box 49, 21pt into 16.3, is in
            // no line of Word's print.)
            // (A group's boxes set in one text carry their right insets.)
            else if RichTextTheme.wordWindowsPages, p.cell == nil,
                    let frame = _fixedTextFrame.map({ $0.right - ownLeft }) ?? style.boxInsetRight.map({ textWidth + _px($0) }),
                    lead >= frame - 0.01 {
                RuleTrace.hit("word-box-first-line-indented-past-the-box-hides-first-word")
                p = Self._hidingFirstWord(p)
            }
            // (In the body, a right-aligned paragraph whose first line is indented to the
            // margin or past it has its first character alone on a first line that shows nothing: windows' lab
            // footx, zh-51af781b's footer "X元阳县人民政府发布" under a 320pt first-line indent
            // has its "元" on a line of its own that shows nothing, the rest from the next; "YZ"
            // draws "Z" with the text, "YYY" "YY".)
            if RichTextTheme.wordWindowsPages, p.cell == nil, _fixedTextFrame == nil, style.boxInsetRight == nil,
               style.alignment == .right, !p.text.isEmpty, !p.runs.contains(where: { $0.style.hidden }) {
                RuleTrace.hit("word-body-first-line-indented-past-the-margin-drops-its-first-character")
                p = Self._hidingFirstWord(p, characterOnly: true)
            }
            // (The first character's em: zh-70094a34's footer opens with
            // a 16pt "山" after a drawing's anchor, over 14pt text, and an
            // em of the text's left it no room — the line held nothing.)
            let em = _px(_firstTextRun(p)?.style.fontSize ?? p.runs.last?.style.fontSize ?? p.style.mark?.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize)
            let past = lead
            lead = max(0, textWidth - em)
            // (The clear copy of a score kept for the print stands where Word's does, past the cell.)
            if p.runs.contains(where: { $0.style.unseen }) { _unseenShift[i] = past - lead }
        }
        }
        _q2()
        }
        _blk1()
        // PowerPoint's bullet with no hanging indent (indent ≥ 0): the
        // bullet stands at the first line's start and the text follows it
        // on that line — ececapstone's "•Down Syndrome…", where the text
        // waited at the next line's edge.
        if theme.markersAtHang, style.list != nil, !p.text.isEmpty,
           _px(style.firstLineIndent) >= _px(theme.listIndent) - 0.01, let label = listLabel(i, document) {
            let marker = _hangMarker(i, p, document, label: label)
            lead = _px(style.firstLineIndent) - _px(theme.listIndent) + marker.width
            marker.dispose()
        }
        // A hanging bullet wider than its hang pushes the first line's text
        // right, to just after it, instead of the bullet standing back over
        // the margin: lo-smartart-bullet-list's 25.4 pt bullet over a hang of
        // 22.5, the text 25.4 in.
        if theme.markersAtHang, style.list != nil, !p.text.isEmpty,
           _px(style.firstLineIndent) < _px(theme.listIndent) - 0.01, let label = listLabel(i, document) {
            let marker = _hangMarker(i, p, document, label: label)
            let hang = _px(theme.listIndent) - _px(style.firstLineIndent)
            if marker.width > hang + 0.01 { lead = marker.width - hang }
            marker.dispose()
        }
        @inline(never) func _blk2() {
        if let wl = wordList, let label = listLabel(i, document) {
            let marker = _marker(i, p, document, label: label, strut: nil)
            // (A number set right — `w:lvlJc` right — ends where the first
            // line starts, as it is drawn; centred, half of it past. Its
            // tab goes on from there: zh-f2ca3070's "i." ends at its
            // hanging indent's start and Word sets "國內新創企業…" at the
            // indent, 7pt on; measured as starting there, ours ended past
            // the indent and its text went to the next default stop.)
            let back = theme.wordRules ? (wl.format?.justification == "right" ? marker.width : wl.format?.justification == "center" ? marker.width / 2 : 0) : 0
            var end = _px(wl.first) + marker.width - back
            switch wl.format?.suffix {
            case "nothing": break
            case "space":
                let spaced = _marker(i, p, document, label: label + "\u{A0}", strut: nil)
                end = _px(wl.first) + spaced.width - back
                spaced.dispose()
                // (After a number in an East Asian face, Word for Windows
                // sets the space in Arial, a 0.278 em: zh-d45f16c4's 14pt
                // 標楷體 "1." has its text 3.84 on in Word's print, 45 lines
                // so, where ours took the face's half em and every item's
                // first line held a character fewer; zh-753cd6a8's SimSun
                // numbers too.)
                // (So too where the level hints its number East Asian and the number has East Asian
                // characters, whatever Latin face the paragraph names: zh-27fc8f9d's bold "第%1条",
                // `w:hint` eastAsia over a Times paragraph, has its text 0.28 em on in Word's print, 18
                // lines so; ours took Times' quarter em and its "…节点：" line took the "点：" Word sends down.)
                let markerChar = _markerChar(p, document), named = _named(p, document)
                let hintedEastAsian = theme.wordRules
                    && (p.style.listId.flatMap({ document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.numberRPrXML })?.containsSubstring("w:hint=\"eastAsia\"") ?? false)
                    && label.contains(where: { Self.isEastAsian($0, hinted: false) })
                if theme.wordRules, RichTextTheme.wordWindowsPages,
                   let face = _levelNumberFonts(p, document).latin ?? markerChar.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily,
                   hintedEastAsian || theme.faceResolver?(face, false)?.isEastAsian == true {
                    let size = _px(_levelNumberSize(p, document) ?? markerChar.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize) * fontScale
                    // (Arial's own space, 569 of 2048: zh-27fc8f9d's "…22个节点：" is 8.0453pt over with it, past
                    // half "节" by the tolerance a line with Latin text keeps, and Word sends "点：" down; at
                    // 0.2778 it was 8.0448 and ours took it.)
                    end = _px(wl.first) + marker.width + 569.0 / 2048.0 * size - back
                }
            default:
                // (A tab stop of the paragraph's own between the number's
                // end and the indent takes the text first: zh-64044a1d's
                // heading 4 has a stop at 840 twips and its hanging indent
                // at 851, and Word starts "(三) 災害…" at the stop — the
                // line then holds one character more.)
                // (With no hanging indent, any stop of the paragraph's past
                // the number, however far: bug65649's "3.2.1.3." ends at
                // 67.6pt under a first-line indent, and Word starts the
                // text at the paragraph's stop at 92.15 — not the default
                // stop at 70.8, where ours set it and its line took a word
                // more than Word's.)
                // (Nor with one, where the number runs past the indent: the
                // paragraph's next stop, before any default one. zh-cec9d337's
                // "（十七）" ends at 60pt over a 49.65pt indent with stops at
                // 49.65 and 63.8, and Word starts "4月20日…" at 63.8; ours went
                // to the default stop at 72, and the line lost a character.)
                let ownStop = theme.wordRules
                    ? style.tabStops.filter { $0.rawKind != "bar" && $0.rawKind != "clear" }.map { _px($0.position) }.sorted()
                        .first(where: { $0 > ownLeft + end + 0.01 && ($0 < ownLeft - 0.01 || wl.first >= 0 || end > 0.01) }) : nil
                // (A number that ends exactly on a stop of the paragraph's own, a right-set "iv." under a 1440 indent and a stop at 1440,
                // is taken to that stop with no width, so the tab the text opens with goes on to the next: sa1 462c594f "iv." has its
                // text at the 2160 stop in Word's print, not the 3600 one.)
                let onOwnStop = theme.wordRules && RichTextTheme.wordWindowsPages && ownStop != nil && wl.first == 0 && abs(end) < 0.01
                    && style.tabStops.contains(where: { $0.rawKind != "bar" && $0.rawKind != "clear" && abs(_px($0.position) - ownLeft) < 0.01 })
                // (Where the settings say `w:doNotUseIndentAsNumberingTabStop`,
                // the default stops before the hanging indent count too:
                // the text goes to the first of the next one and the
                // indent. zh-447f1d5c's Wingdings bullets end at 120.5pt over
                // an indent at 128.75, and Word starts their text at the
                // default stop at 121.4 (840 twips); ours, at the indent,
                // held three characters fewer a line. zh-fec5fa30's "1."
                // ends at 115.6 with its indent at 124.9 before the stop
                // at 126, and its text starts at the indent.)
                if onOwnStop {
                    end = 0
                    RuleTrace.hit("word-number-ending-on-own-stop-takes-it")
                } else if let stop = ownStop {
                    end = stop - ownLeft
                } else if wl.first < 0, end <= 0.01, theme.wordRules, document.indentNotNumberingTabStop,
                          case let tab = _px(document.defaultTabStop ?? 36), tab > 0.01 {
                    let from = ownLeft + end
                    // (A number that ends on the indent has it no longer ahead: the default stop takes the
                    // text. zh-12c4f07a's 14pt "3.3.2.10." fills its 63pt hang and Word starts "乙方…" at
                    // the stop at 120pt, 12.4 past the indent; ours, at the indent, held a character more.)
                    let next = ((from / tab + 0.001).rounded(.down) + 1) * tab - ownLeft
                    end = end > -0.01 ? next : min(0, next)
                } else if wl.first < 0, end <= 0.01 {
                    end = 0
                } else if theme.wordRules, wl.first < 0, p.cell != nil {
                    // (In a table's cell a number that runs past the hanging
                    // indent has its text straight after it, with no tab to
                    // a default stop: zh-ae655121's notes cell, "二、" 26pt
                    // wide in a 24pt hang, sets "法人提報…" at the number's
                    // end in Word's print, where ours went to the next stop
                    // 18pt on and the line held two characters fewer. The
                    // same document's body lists, the same way over their
                    // hang, do go to the next stop.)
                } else {
                    // (No default stops at all — `w:defaultTabStop` 0, as
                    // some files say — and the text follows the number.)
                    let tab = _px(document.defaultTabStop ?? 36)
                    let from = ownLeft + end
                    if tab > 0.01 { end = ((from / tab + 0.001).rounded(.down) + 1) * tab - ownLeft }
                }
            }
            marker.dispose()
            lead = end == 0 ? 0.01 : end
            // (Centred or set right, the number goes with its line —
            // "第一章 总则" is centred whole — so the box before the
            // text is all of the number and its gap.)
            if style.alignment == .center || style.alignment == .right { lead = max(0.01, end - _px(wl.first)) }
            // (A centred line with a first-line indent — a positive `wl.first` — is centred in what the indent leaves:
            // jpn-8787f4's "四、パラダイム転換…" heading, firstLine 480, centred over 114 to 505 in Word's print, held 32
            // characters where ours, centred over the whole width, held 33.)
            if style.alignment == .center, theme.wordRules, RichTextTheme.wordWindowsPages, _px(wl.first) > 0.01 { lead = max(0.01, end) }
        }
        }
        _blk2()
        _leadWidth[i] = lead
        // Tabs, as Word sets them: each takes the text to the next stop —
        // the paragraph's own, the hanging indent, then the document's
        // default distance apart — and a centred, right or decimal stop
        // sets what follows about it. The engine gives a tab no width of
        // its own, so each is widened by what its stop needs.
        var tabs: [Int: Double] = [:]
        // What stands past the margin after a right stop at it (or set
        // there), by the offset of its last character: drawn there,
        // taking no room.
        var hangs: [Int: Double] = [:]
        // The tabs to a right stop at the margin (or set there): what
        // follows one that starts inside it may run past the margin, and
        // the line fitting is told so.
        var runsPast: Set<Int> = []
        var clampedStops: Set<Double> = []
        // A right stop honoured past the margin: how far past (tab offset -> points in px).
        var beyond: [Int: Double] = [:]
        let pictureTabs = Self._picturesAndTabs(p)
        var atMargin: Set<Int> = []
        var leftTabs: Set<Int> = []    // tabs that take a first line's label to its hanging indent
        var lonePastTabs: Set<Int> = []  // a lone tab whose default stop is past the margin: held, goes down
        var beforeTabs: Set<Int> = []  // spaces a justified line does not stretch: before its last tab
        _leaders[i] = []
        // (PowerPoint's the same way: its stops from the text's left, the
        // hanging indent first, then `defTabSz` apart — HowWeRefactor's
        // quotes, their first line at the indent and "– Martin Fowler" at
        // the seventh inch, PowerPoint's print to a tenth of a point.)
        // (The lines' own insets beside a float, once they are known: a tab is measured from the margin, so a line the float
        // holds in starts its tabs that far along, and a stop past the window's far edge is Word's, not the column's.)
        var tabWindows: [LineIndent] = []
        var forcedWraps: Set<Int> = []
        var afterTabWraps: Set<Int> = []
        @inline(never) func _blk3() {
        if theme.wordRules || theme.markersAtHang, !style.rightToLeft || theme.wordRules, p.text.utf16.contains(0x09) {
            let (probeSpan, probeInline, probeInserts) = _span(for: p, at: i, document, textWidth: textWidth, lead: lead)
            let probe = TextPainter(text: probeSpan, textAlign: .left, textDirection: .ltr)
            if !probeInline.isEmpty { probe.setPlaceholderDimensions(probeInline.map { $0.dimensions }) }
            probe.layout(minWidth: 0, maxWidth: 10_000_000)
            let probeMap = _OffsetMap(lead: lead != 0 ? 1 : 0, inserts: probeInserts)
            // (Each character's left edge, by its box: the caret after a
            // tab is not at the tab's far side.)
            func edge(_ offset: Int) -> Double {
                if offset >= units.count {
                    let last = probeMap.painter(units.count - 1)
                    return probe.getBoxesForSelection(TextSelection(baseOffset: last, extentOffset: last + 1)).last?.right ?? 0
                }
                let at = probeMap.painter(offset)
                return probe.getBoxesForSelection(TextSelection(baseOffset: at, extentOffset: at + 1)).first?.left
                    ?? probe.getOffsetForCaret(TextPosition(offset: at), Rect.zero).dx
            }
            let units = Array(p.text.utf16)
            let stops = style.tabStops.sorted { $0.position < $1.position }
            let step = _px(document.defaultTabStop ?? 36)
            // `wraps`: where the lines the column wraps the paragraph into
            // start (PowerPoint's, measured below); a tab on such a line
            // is measured from the line's own start, at the indent.
            // (The line starts at its left edge: the engine no longer moves
            // it on by half its first character's spacing — starling-engine's
            // patches/skia-no-line-spacing-shift.patch.)
            let origin = 0.0
            func measure(_ found: [Int]) {
            // (A line start the trial lays out at a hard break's own character
            // is the character after it: LibreOffice's tdf146248 sets each
            // contents entry after the first on a line of its own by `w:br`,
            // and measured its tab from the end of the line before, a negative
            // distance, so every page number went to a line of its own.)
            var wraps = found.map { w in w < units.count && (units[w] == 0x0A || units[w] == 0x2028) ? w + 1 : w }
            if tabWindows.isEmpty { forcedWraps = [] } else if !forcedWraps.isEmpty { wraps = Array(Set(wraps).union(forcedWraps)).sorted() }
            if !afterTabWraps.isEmpty { wraps = Array(Set(wraps).union(afterTabWraps)).sorted() }
            // (A word that ends in a tab, the line it would end short by a hair of the room — the
            // engine's strict fit sends it down, and the line fitting takes it back up: the tab
            // then stands where the line breaks before it, at the line's start, as Word's does.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, !style.rightToLeft, wraps.first != nil {
                let w = wraps[0]
                if w > 0, let t = (w ..< units.count).first(where: { units[$0] == 0x09 }),
                   !(w ..< t).contains(where: { units[$0] == 0x20 || units[$0] == 0x0A || units[$0] == 0x2028 }) {
                    if edge(t) - textWidth <= _px(1.5) {
                        wraps[0] = t
                        RuleTrace.hit("word-before-a-tab-keeps-its-line")
                    }
                }
            }
            // (A run of two or more tabs that stands past the margin goes down to the next line whole, and
            // its stops start again there: the trial lays the tabs out hanging and breaks after them, the
            // final layout holds them and breaks before. Word's zh-77bd4900 p10: three tabs after an
            // ideograph end at 84/108/132 from the line's start, not on the grid of the line above.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, !style.rightToLeft {
                for (k, w) in wraps.enumerated() where w > 1 && w <= units.count && units[w - 1] == 0x09 {
                    var t0 = w - 1
                    while t0 > 0, units[t0 - 1] == 0x09 { t0 -= 1 }
                    // (A lone tab after a space, on a paragraph with no stops of its own, goes down too: its default
                    // stop is past the margin, and Word's line starts with the tab, text at the next stop.)
                    let loneAfterSpace = w - t0 == 1 && t0 > 0 && units[t0 - 1] == 0x20 && stops.isEmpty
                    // (And the word after it must fit past the tab too: Word keeps the tab with the word, so
                    // "Grant <tab>Contract" whose "Contract" would cross the margin sets the tab on the next line.)
                    var wordEnd = w
                    while wordEnd < units.count, units[wordEnd] != 0x20, units[wordEnd] != 0x09, units[wordEnd] != 0x0A, units[wordEnd] != 0x2028 { wordEnd += 1 }
                    let wordAfter = loneAfterSpace && wordEnd > w ? edge(wordEnd) - edge(w) : 0
                    // (A run of tabs with nothing after it to set (paragraph or line end) does not restart on the next line: its
                    // stops sit within the margin. sa1 b0e39b18, tabs before a line break: one line in Word.s print.)
                    var runEnd = w
                    while runEnd < units.count, units[runEnd] == 0x09 { runEnd += 1 }
                    if runEnd >= units.count || units[runEnd] == 0x0A || units[runEnd] == 0x2028 { continue }
                    guard w - t0 >= 2 || loneAfterSpace, t0 > 0, loneAfterSpace || units[t0 - 1] != 0x20, units[t0 - 1] != 0x0A, units[t0 - 1] != 0x2028,
                          k == 0 || wraps[k - 1] < t0,
                          edge(t0 + 1) + (tabs[t0] ?? 0) + (loneAfterSpace ? wordAfter : 0) > textWidth + _px(0.5) else { continue }
                    wraps[k] = t0
                    if loneAfterSpace { lonePastTabs.insert(t0) }
                    RuleTrace.hit("word-tab-run-past-the-margin-restarts-its-stops-on-the-next-line")
                }
            }
            // (The same lone tab after a space, with words after it on the line before the break: its default
            // stop past the margin, it opens the next line with them. Word's gv-d1907c960c "of this <tab>Grant".)
            if theme.wordRules, RichTextTheme.wordWindowsPages, !style.rightToLeft, stops.isEmpty {
                for (k, w) in wraps.enumerated() where w > 2 && w <= units.count {
                    let lineStart = k == 0 ? 0 : wraps[k - 1]
                    guard w - 1 >= lineStart, let t = (lineStart ..< w - 1).last(where: { units[$0] == 0x09 }), t > lineStart + 1, units[t - 1] == 0x20,
                          units[t + 1] != 0x09, units[t - 2] != 0x09, (t + 1 ..< w).contains(where: { units[$0] != 0x20 }),
                          edge(t + 1) - (lineStart > 0 ? edge(lineStart) : 0) + (tabs[t] ?? 0) > textWidth + _px(0.5) else { continue }
                    wraps[k] = t
                    lonePastTabs.insert(t)
                    RuleTrace.hit("word-tab-with-words-after-it-past-the-margin-opens-the-next-line")
                }
            }
            tabs = [:]
            hangs = [:]
            runsPast = []
            clampedStops = []
            beyond = [:]
            atMargin = []
            leftTabs = []
            _leaders[i] = []
            var shift = 0.0
            var lastTab = 0
            var base: Double? = nil
            var ordinal = -1
            for (t, u) in units.enumerated() where u == 0x09 {
                ordinal += 1
                // (A line break since the last tab: the line starts over.)
                if units[lastTab ..< t].contains(where: { $0 == 0x0A || $0 == 0x2028 }) { shift = 0 }
                // (A wrap offset on a line-break character is that line's end: the next
                // line starts after it, at its left edge: tdf146248's contents entries
                // "Record Types<tab>10" after a <w:br/> had their right tab measured
                // from the end of the line before and "10" went to a line of its own.)
                if let w = wraps.last(where: { $0 > lastTab && $0 <= t }) {
                    shift = 0
                    base = edge(units[w] == 0x0A || units[w] == 0x2028 ? min(w + 1, t) : w)
                }
                lastTab = t
                // (A right-to-left paragraph's tabs are measured from its
                // start, the right edge, where what stands before the tab on
                // its line has no right-to-left letters — digits, other tabs:
                // the note numbers of lo-ccca8bf3 (tdf129659), "1<tab><tab>" —
                // and for left, right and centred stops; the probe is laid out
                // left to right, whose advances are the same.)
                // (What stands before the tab on its line is as wide as its
                // boxes spread — Hebrew stands reversed in the probe, so its
                // offsets say nothing — and starts at the lead, where the
                // line is the paragraph's first.)
                var rtlAt: Double? = nil
                if style.rightToLeft {
                    let lineStart = (0 ..< t).last(where: { units[$0] == 0x0A || units[$0] == 0x2028 }).map { $0 + 1 } ?? 0
                    let rtlLetter: (UInt16) -> Bool = { ($0 >= 0x0590 && $0 <= 0x08FF) || ($0 >= 0xFB1D && $0 <= 0xFDFF) || ($0 >= 0xFE70 && $0 <= 0xFEFF) }
                    if units[lineStart ..< t].contains(where: rtlLetter) {
                        if base != nil || lineStart != 0 { continue }
                        let boxes = probe.getBoxesForSelection(TextSelection(baseOffset: probeMap.painter(0), extentOffset: probeMap.painter(t - 1) + 1))
                        guard let lo = boxes.map(\.left).min(), let hi = boxes.map(\.right).max() else { continue }
                        rtlAt = lead + (hi - lo)
                    }
                    let here = stops.first(where: { _px($0.position) > ownLeft + (rtlAt ?? edge(t)) - (base ?? origin) + shift + 0.5 })
                    if let here, here.alignment == .decimal { continue }
                }
                let at = rtlAt ?? edge(t)
                var after = edge(t + 1)
                if style.rightToLeft {
                    // (The next character is Hebrew, which the left-to-right
                    // probe sets at the far end of its run: the tab's own
                    // box is its width.)
                    let me = probeMap.painter(t)
                    let box = probe.getBoxesForSelection(TextSelection(baseOffset: me, extentOffset: me + 1)).first
                    after = at + max(0, (box?.right ?? at) - (box?.left ?? at))
                }
                // from the column's left
                // (Less the engine's shift of the line by half its first
                // character's spacing, where that is drawn back: the line
                // is as wide as its advances, and zh-10e3a42b's "1．总则
                // <tab>4", the "1" spaced -0.5, came out 0.25 past its stop
                // — 0.05 past the column, the "4" on a line of its own. A
                // spacing that pushes the line on keeps the stop drawn.)
                let windowLine = wraps.filter { $0 <= t }.count
                let window = windowLine < tabWindows.count ? tabWindows[windowLine] : LineIndent()
                let x = (base.map { ownLeft + at - $0 + shift } ?? ownLeft + at - origin + shift) + window.left
                // (A tab whose next character's edge the probe cannot give — its box missing, the caret read as 0 — has the width
                // of its own box: xd 6be5dbc9's "३.<tab>संस्थाको", the tab taken as 27 pt wide, already at its hanging stop, so it
                // got no stretch and stood 3 pt wide in Word's 27.)
                if theme.wordRules, !style.rightToLeft,
                   let own = probe.getBoxesForSelection(TextSelection(baseOffset: probeMap.painter(t), extentOffset: probeMap.painter(t) + 1)).first,
                   own.right > own.left, after - at > own.right - own.left + _px(1),
                   probe.getBoxesForSelection(TextSelection(baseOffset: probeMap.painter(t + 1), extentOffset: probeMap.painter(t + 1) + 1)).isEmpty {
                    after = at + (own.right - own.left)
                    RuleTrace.hit("word-tab-width-is-its-own-box-when-the-next-edge-is-missing")
                }
                // (A tab whose next character's edge lies BEFORE the tab's own, the probe putting a tab that starts a differently
                // styled run behind it: the tab has the width of its own box, not a negative one. sa1 b0e39b18's fourteen tabs, the
                // 6th and 7th not underlined between underlined ones: the 7th measured -348 twips, was stretched 406 too far and
                // the 14th tab went down to a line of its own, the page below it one line low.)
                // (On the tab's own line: a tab ending its line has the next character on the line below, its edge
                // behind by the whole line, and keeps its width; dx2 th 3578a03d.)
                if theme.wordRules, !style.rightToLeft, after < at - 0.01,
                   let own = probe.getBoxesForSelection(TextSelection(baseOffset: probeMap.painter(t), extentOffset: probeMap.painter(t) + 1)).first,
                   own.right > own.left,
                   let nextBox = probe.getBoxesForSelection(TextSelection(baseOffset: probeMap.painter(t + 1), extentOffset: probeMap.painter(t + 1) + 1)).first,
                   abs(nextBox.top - own.top) < 1 {
                    after = at + (own.right - own.left)
                    RuleTrace.hit("word-tab-width-is-its-own-box-when-the-next-edge-lies-behind-it")
                }
                let own = after - at
                var stop: (x: Double, alignment: TabStop.Alignment, leader: String?)? = nil
                if let s = stops.first(where: { _px($0.position) > x + 0.5 && !clampedStops.contains(_px($0.position)) }) { stop = (_px(s.position), s.alignment, s.leader) }
                var toIndent = false
                if lead < 0, ownLeft > x + 0.5, stop.map({ ownLeft < $0.x }) ?? true { stop = (ownLeft, .left, nil); toIndent = true }
                if !toIndent, Self._honoursStopsPastMargin(document), let s = stop, s.alignment == .left, s.x > ownLeft + textWidth + 0.5, stops.contains(where: { abs(_px($0.position) - s.x) < 0.01 }) { _pastLeft[i] = max(_pastLeft[i] ?? 0, s.x - (ownLeft + textWidth)) }
                if stop == nil, step > 0 { stop = (((x + 0.5) / step).rounded(.down) * step + step, .left, nil) }
                // (A positional tab goes to its place on the margins, past
                // the stops between: bug57031's footer has "Page 2 of 14"
                // after a right ptab that is its first tab, and Word ends it
                // at the right margin, where the Footer style's centre stop
                // took ours to the middle.)
                if theme.wordRules, let a = style.positionalTabs[ordinal] {
                    stop = (a == .right ? width : a == .center ? width / 2 : 0, a, nil)
                }
                // (A right or centred stop past the right indent sets what
                // follows flush against it: zh-c2c92639's "toc 1" has its
                // dotted right stop at 13948 twips, past the page, and Word
                // ends every entry's page number at the margin. Lab `tb`,
                // Word for Windows: stops at 9600, 9800, 11000 and 13948
                // twips in a 9264-twip line all end "123" at the margin,
                // centred ones too; ours ran the dots on to the stop and
                // the number went to a line of its own.)
                if theme.wordRules, var s = stop, s.alignment == .right || s.alignment == .center,
                   s.x > ownLeft + textWidth + 0.5 + ((s.leader.map { $0 != "none" && !$0.isEmpty } ?? false) && s.alignment == .right && style.alignment != .justify ? _px(Self._tabPastMargin) : 0) {
                    clampedStops.insert(s.x)
                    if Self._honoursStopsPastMargin(document) { _pastNeed[i] = max(_pastNeed[i] ?? 0, s.x - (ownLeft + textWidth)) }
                    s.x = ownLeft + textWidth
                    s.alignment = .right
                    stop = s
                    atMargin.insert(t)
                }
                // (A right or centred stop past the edge of the window a float leaves, a tab following: that tab goes
                // down to the next line, its stops measured again there; the paragraph's last one is set against the
                // window's edge. Word's print of lab ellhdr, five tabs between two boxes in a 4pt line: one tab on each
                // of three lines, the last two on a fourth, a sixth tab making five lines.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, window.right > 0, var s = stop, s.alignment == .right || s.alignment == .center,
                   s.x > ownLeft + textWidth - window.right + 0.5 {
                    s.x = ownLeft + textWidth - window.right
                    if units[(t + 1)...].contains(0x09) {
                        // this tab fills its line; the next starts a new one
                        s.alignment = .left
                        let lineFrom = wraps.last(where: { $0 <= t }) ?? 0
                        if units[lineFrom ..< t].contains(0x09), !forcedWraps.contains(t) {
                            forcedWraps.insert(t)
                            measure(wraps)
                            return
                        }
                    } else { s.alignment = .right }
                    stop = s
                    RuleTrace.hit("word-last-tab-beside-a-float-stops-at-its-window-edge")
                }
                // (No stop to go to — no stops of its own and no default
                // distance, `w:defaultTabStop` 0 — and the tab takes no
                // room: zh-77079ee8's 28pt cell "<tab>宣導說明會" sets "宣"
                // on the tab's line in Word's print, five lines centred in
                // the row; ours gave the tab its own and stood 10pt low.
                // Only a paragraph's or line's leading tab: zh-c15af02e's
                // mid-line "多，<tab>顯有未合" keeps its width in Word.)
                if stop == nil, step <= 0.01, theme.wordRules,
                   t == 0 || units[t - 1] == 0x0A || units[t - 1] == 0x2028 { tabs[t] = -own; continue }
                guard let stop else { continue }
                // What follows, up to the next tab or the line's end.
                var end = t + 1
                while end < units.count, units[end] != 0x09, units[end] != 0x0A, units[end] != 0x2028 { end += 1 }
                var following = max(0, edge(end) - after)
                // (Spaces that END the paragraph after a right or centre tab hang: sa1 7770c637's contents "<tab>3 " stands its 3 at
                // 481.06, the right edge of the stop, where "11" without one ends at it too; ours counted the space and stood 6 pt left.)
                if theme.wordRules, !style.rightToLeft, stop.alignment == .right || stop.alignment == .center, end == units.count, end > t + 1,
                   units[end - 1] == 0x20 {
                    var e2 = end
                    while e2 > t + 1, units[e2 - 1] == 0x20 { e2 -= 1 }
                    following = max(0, edge(e2) - after)
                    RuleTrace.hit("word-spaces-ending-the-paragraph-after-a-right-tab-hang")
                }
                if style.rightToLeft, end > t + 1 {
                    // (Right-to-left letters stand reversed in the probe: the
                    // run's width is its boxes' spread, not the offsets'.)
                    let from = probeMap.painter(t + 1), to = probeMap.painter(end - 1) + 1
                    let boxes = probe.getBoxesForSelection(TextSelection(baseOffset: from, extentOffset: to))
                    if let lo = boxes.map(\.left).min(), let hi = boxes.map(\.right).max() { following = max(0, hi - lo) }
                }
                // (A run of tabs that ends the paragraph: a tab that starts past the margin goes to the next line, and the stops
                // start again there, from the line's own start. The probe sets the run on one long line and the final layout wraps
                // it, so the tabs after the wrap kept their widths from the stops of the first line: sa1 9994f234's "OTRO:)" and 38
                // tabs, stops at 1080, 1440, 2160... twips; Word's second line goes 90, 126, 144, 180, 216 pt, ours 90, 126, 162, 198
                // on a grid, a line more in all, the signature block of the page on the next one.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, !style.rightToLeft, t > 0, x > ownLeft + textWidth + 0.5, units[t - 1] == 0x09,
                   units[t...].allSatisfy({ $0 == 0x09 }), !wraps.contains(t), !afterTabWraps.contains(t) {
                    afterTabWraps.insert(t)
                    RuleTrace.hit("word-tab-run-ending-the-paragraph-restarts-its-stops-past-the-margin")
                    measure(wraps)
                    return
                }
                var extra = stop.x - x - own
                switch stop.alignment {
                case .left: break
                case .center: extra -= following / 2
                case .right:
                    extra -= following
                    // (A right stop clamped to the margin ends the line exactly AT it, and a float's rounding then wraps the
                    // text: 462c594f's "<tab>Página" at a stop 389 twips out stood alone on a second line, Word's at the margin.)
                    if theme.wordRules, atMargin.contains(t) { extra -= 0.02 }
                case .decimal:
                    if let dot = (t + 1 ..< end).first(where: { units[$0] == 0x2E }) { extra -= edge(dot) - after } else { extra -= following }
                }
                // (A stop nearer than the engine's own tab width: the tab
                // is that narrow. Word sets bug65649's "5.1.1.<tab>" at
                // its stop 1.35pt on; ours kept the tab's 3pt, and the
                // line's nine spaces then had 0.87pt each to give — past
                // their quarter — so "выполнения" went over. Word's
                // print has them at 2.31, the line filled to the margin.)
                // (A centred or right stop that the text after it is too wide to be set at, where the tab's own width would
                // push the text past the margin but the text alone fits: the tab takes no room and the text starts where the
                // tab stood. sa2 81f316d6's header, "<tab>" + 138 spaces + "Comité de Selección" (472.9 pt of 473) at a centre
                // stop at 212 pt: Word's print starts the spaces at the margin and keeps one line; ours gave the tab 2.7 pt and
                // sent "Selección" down. Lab tbhdrwrap, Word for Windows.)
                var collapsedTab = false
                if theme.wordRules, RichTextTheme.wordWindowsPages, stop.alignment == .center || stop.alignment == .right, extra < 0,
                   x + following <= ownLeft + textWidth + 0.01, x + own + following > ownLeft + textWidth + 0.01 {
                    collapsedTab = true
                    RuleTrace.hit("word-wide-centred-tab-takes-no-room-when-the-text-just-fits")
                }
                extra = stop.alignment == .left ? max(0.5 - own, extra) : max(0, extra)
                // (A justified paragraph's trailing tabs, the last stop at the margin's edge: that tab is set as a
                // tab, not as a held space, which is a hair wider and wrapped it. sa1 b0e39b18, "Hearing Time:
                // <4 tabs>" in a justified line, one line in Word's print, ours wrapped the last tab and
                // moved the lines below it 17 pt.)
                if theme.wordRules, style.alignment == .justify, stop.alignment == .left, abs(stop.x - (ownLeft + textWidth)) < 0.01,
                   (t + 1 ..< units.count).allSatisfy({ units[$0] == 0x09 || units[$0] == 0x20 }) {
                    atMargin.insert(t)
                }
                if collapsedTab { extra = -own }
                // Trailing tabs do not open an empty line beyond the
                // margin. Keep their stops within the remaining width.
                // (Tabs that end a paragraph after a tab that reached the margin stay on that line, taking no width: Word's
                // print of cc08e083's header, picture, tab, spaces, right tab at the margin and two more tabs, one line,
                // ours a second. Lab hdr-tab-float, Word for Windows: the same with and without the anchored picture.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, !pictureTabs, !style.rightToLeft, t > 0, units[t - 1] == 0x09,
                   stop.alignment == .left, style.tabStops.contains(where: { $0.alignment == .right && abs(_px($0.position) - x) < 0.01 }), abs(x - (ownLeft + textWidth)) < 0.01, stop.x > ownLeft + textWidth + 0.01,
                   units[t...].allSatisfy({ $0 == 0x09 }) {
                    extra = min(extra, -own)
                    RuleTrace.hit("word-tabs-after-a-tab-at-the-margin-take-no-width")
                }
                if theme.wordRules, pictureTabs, units[(t + 1)...].allSatisfy({ $0 == 0x09 }) {
                    extra = min(extra, max(0, ownLeft + textWidth - x) - own)
                }
                // (A left stop past the right indent but inside the margin is a stop Word
                // honours — the indent does not bound the stops — so a tab run that ends the
                // paragraph stays on the line: dx2 cbb7ae39's "…हस्ताक्षरित<tab><tab>", stops to
                // 10769 twips in a 10765-twip indent edge, the page's margin at 11640; ours sent the
                // tab to a line of its own and the form stood 17pt low from there.)
                if theme.wordRules, !pictureTabs, !style.rightToLeft, stop.alignment == .left, right > 0,
                   stop.x > ownLeft + textWidth + 0.01, stop.x <= ownLeft + textWidth + right,
                   units[(t + 1)...].allSatisfy({ $0 == 0x09 }) {
                    extra = min(extra, max(0, ownLeft + textWidth - x) - own)
                    RuleTrace.hit("word-trailing-left-tab-inside-the-margin-stays-on-its-line")
                }
                // (An EXPLICIT left stop past the margin itself, the tab run ending the paragraph with the text short of
                // the margin: the tab fills to the margin and stays on its line in Word's print. sa2 3c4382f0's "Eu, <tab>",
                // stop 9683 twips in an 8504-twip measure, the next paragraph one line below; ours sent the tab down.)
                                if theme.wordRules, RichTextTheme.wordWindowsPages, !pictureTabs, !style.rightToLeft, style.alignment == .justify, stop.alignment == .left,
                   stop.x > ownLeft + textWidth + 0.01 + right, x + own < ownLeft + textWidth - 0.5,
                   stops.contains(where: { $0.alignment == .left && abs(_px($0.position) - stop.x) < 0.01 }),
                   units[(t + 1)...].allSatisfy({ $0 == 0x09 }) {
                    extra = -own
                    RuleTrace.hit("word-explicit-trailing-left-tab-past-the-margin-stays-on-its-line")
                }
                // (A left stop at or past the right indent but inside the margin, text after its tab that ends
                // inside the margin too: the text stands at the stop on the line, over the indent, as in
                // Word's print of xd 94baf8b9bd's contents, "NDCO program aims and outcomes<tab>5" in a
                // style with the stop at 8647 twips and a right indent edge at 8647 less its 686; ours sent the number to
                // a second line and the list ran a page long. Digits only (a page number): a footer's
                // words after such a stop (dx2-class xd 708e2879's "Appendices", set at the stop in Word's print) are
                // squeezed by this and vanish or break inside the word; they keep the old placing.)
                if theme.wordRules, !pictureTabs, !style.rightToLeft, stop.alignment == .left, right > 0, following > 0.01,
                   stop.x >= ownLeft + textWidth - 0.01, stop.x + following <= ownLeft + textWidth + right + 0.01,
                   x + own < stop.x - 0.01, hangs[t + 1] == nil, (t + 1 ..< end).allSatisfy({ units[$0] >= 0x30 && units[$0] <= 0x39 }),
                   let last = (t + 1 ..< end).last(where: { units[$0] != 0x20 }), hangs[last] == nil {
                    let over = stop.x + following - (ownLeft + textWidth) + 0.05
                    let span = max(0.01, edge(last + 1) - after)
                    if over < edge(last + 1) - edge(last) - 0.5 {
                        hangs[last] = -over
                    } else {
                        for k in t + 1 ... last where units[k] != 0x20 { hangs[k] = -over * max(0, edge(k + 1) - edge(k)) / span }
                    }
                    atMargin.insert(t)
                    RuleTrace.hit("word-left-tab-text-past-the-right-indent-stays-on-its-line")
                }
                // (A stop set at the margin that the text before it has
                // nearly reached: what follows the tab stands on past the
                // margin, the line's marks unsqueezed, as Word's print sets
                // zh-ab1ea005's contents — "55.…是否支付经济补偿？<tab>23",
                // its dotted stop past the margin, ends "23" 4.8pt over it;
                // ours sent "23" to a line of its own, and the contents ran
                // a line behind. Only where the tab starts inside its stop:
                // one past it goes down with what follows, T127.)
                if theme.wordRules, !style.rightToLeft, stop.alignment == .right, stop.x >= ownLeft + textWidth - _px(1) { runsPast.insert(t) }
                if theme.wordRules, !style.rightToLeft, stop.alignment == .right, stop.x >= ownLeft + textWidth - _px(1), x + own < stop.x - 0.01,
                   let last = (t + 1 ..< end).last(where: { units[$0] != 0x20 }),
                   case let over = x + own + edge(last + 1) - after - (ownLeft + textWidth), over > 0.01 {
                    // (The tab takes nothing — the number follows the text
                    // straight on in Word's print — and the rest is off the
                    // last character's advance, a hair more, so the line
                    // ends inside the margin and its ink runs on past it.
                    // Where that is more than the character's own advance,
                    // shared out by width over what follows the tab: the
                    // engine keeps no advance under nothing.)
                    extra = -own
                    let rest = over - own + 0.05
                    let span = max(0.01, edge(last + 1) - after)
                    if rest > 0, rest < edge(last + 1) - edge(last) - 0.5 {
                        hangs[last] = -rest
                    } else if rest > 0 {
                        for k in t + 1 ... last where units[k] != 0x20 { hangs[k] = -rest * max(0, edge(k + 1) - edge(k)) / span }
                    }
                }
                // (Not in a justified paragraph: there Word ends the number at the margin, as at any stop past it,
                // 462c594f's contents lines, stop 360 twips out, compat 15.)
                // (A right stop a little past the margin is honoured: lab tabr, Word for Windows,
                // stops 52 to 452 twips past an 8848-twip line all end the number AT the stop, on
                // the line, the dots running on to it. The line stays inside the margin for the
                // engine — the number's last character gives the overshoot up — and its ink
                // ends at the stop. zh-875759ff's contents, stop 105 twips out.)
                if theme.wordRules, style.alignment != .justify, stop.alignment == .right, let lead = stop.leader, lead != "none", !lead.isEmpty,
                   stop.x > ownLeft + textWidth + 0.5, stop.x <= ownLeft + textWidth + _px(Self._tabPastMargin) + 0.5,
                   x + own < stop.x - 0.01, hangs[t + 1] == nil,
                   let last = (t + 1 ..< end).last(where: { units[$0] != 0x20 }), hangs[last] == nil {
                    let over = stop.x - (ownLeft + textWidth)
                    beyond[t] = over
                    let span = max(0.01, edge(last + 1) - after)
                    if over < edge(last + 1) - edge(last) - 0.5 {
                        hangs[last] = -over
                    } else {
                        for k in t + 1 ... last where units[k] != 0x20 { hangs[k] = -over * max(0, edge(k + 1) - edge(k)) / span }
                    }
                    RuleTrace.hit("word-right-tab-past-the-margin-is-honoured")
                }
                // (A tab that starts at the margin and has only a default stop past it
                // goes to that stop, and what follows stands there on the line, over the
                // margin: xa gv-0de3e9bcf1's footer "title<tab>ESAD 2012<tab>2", the
                // right stop 3 twips past the margin, the page number 4.8 pt on at the
                // next default stop of 720 twips; Word's print keeps it on the line,
                // ours sent it to a line of its own and the footer grew a line.)
                if theme.wordRules, !style.rightToLeft, stop.alignment == .left, stop.leader == nil, !toIndent,
                   !stops.contains(where: { _px($0.position) > x + 0.5 && !clampedStops.contains(_px($0.position)) }),
                   x >= ownLeft + textWidth - _px(1), t > 0, hangs[t + 1] == nil, !clampedStops.isEmpty,
                   !(t + 1 ..< end).contains(where: { units[$0] == 0x20 }),
                   let last = (t + 1 ..< end).last(where: { units[$0] != 0x20 }), hangs[last] == nil,
                   case let over = x + own + extra + following - (ownLeft + textWidth), over > 0.01 {
                    let span = max(0.01, edge(last + 1) - after)
                    if over < edge(last + 1) - edge(last) - 0.5 {
                        hangs[last] = -over
                    } else {
                        for k in t + 1 ... last where units[k] != 0x20 { hangs[k] = -over * max(0, edge(k + 1) - edge(k)) / span }
                    }
                    RuleTrace.hit("word-default-tab-at-the-margin-keeps-the-line")
                }
                // (An EXPLICIT left stop past the line's text edge, spaces after its tab to the paragraph's end: the tab
                // fills the line to its edge and the spaces go to a second line at the indent, in Word's print.
                // sa2 d6f66b01's "Médicos AP<spaces><tab><18 spaces>" in a cell, stops at 5445 and 7470 twips in a
                // 4599-twip text width, two lines in Word, ours one; lab tabcell5/6: stops at 4700 twips and past
                // wrap in a 4599-twip width, stops at 3000 and 4400 stay on one line; cell margins, table style,
                // cell width and layout mode do not matter. With only default stops the tab stays on one line.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, !pictureTabs, !style.rightToLeft, stop.alignment == .left, !toIndent,
                   stop.x > ownLeft + textWidth + 0.01, x + own < ownLeft + textWidth - 0.5,
                   stops.contains(where: { $0.alignment == .left && abs(_px($0.position) - stop.x) < 0.01 }),
                   t + 1 < units.count, units[(t + 1)...].allSatisfy({ $0 == 0x20 }) {
                    extra = ownLeft + textWidth - x - own - 0.02
                    if !afterTabWraps.contains(t + 1), !wraps.contains(t + 1) {
                        afterTabWraps.insert(t + 1)
                        measure(wraps)
                        return
                    }
                    RuleTrace.hit("word-explicit-left-tab-past-the-edge-sends-trailing-spaces-to-the-next-line")
                }
                tabs[t] = extra
                if toIndent { leftTabs.insert(t) }
                shift += extra
                if let fill = stop.leader, fill != "none" {
                    let ch = ["dot": ".", "hyphen": "-", "underscore": "_", "middleDot": "\u{B7}", "heavy": "_"][fill] ?? "."
                    _leaders[i].append((t, ch))
                }
            }
            }
            measure([])
            // PowerPoint's tabs on the lines the paragraph wraps into, as
            // laid out with the tabs so far: measured again from where
            // each line starts until the lines stop moving (HowWeRefactor's
            // "– Martin Fowler", on the third line of its quote). Word's
            // the same way: bug65649's cell "…кнопка выхода<tab> ST-EX011SM,
            // Замок электромагнитный<tab> VIZIT-ML400M-40)" sets each tab at
            // the default stop next after where its line has got to — 241.0
            // and 276.4 in Word's print, 35.4pt apart from the cell's edge;
            // measured along the unwrapped paragraph, ours were 227.0 and
            // 284.5, and "40)" went to a line of its own.
            if theme.markersAtHang || theme.wordRules {
                var wraps: [Int] = []
                for _ in 0 ..< 3 {
                    let (s1, in1, ins1) = _span(for: p, at: i, document, textWidth: textWidth, lead: lead,
                                                adjust: hangs.isEmpty ? tabs : tabs.merging(hangs) { $0 + $1 })
                    let trial = TextPainter(text: s1, textAlign: .left, textDirection: style.rightToLeft ? .rtl : .ltr)
                    if !in1.isEmpty { trial.setPlaceholderDimensions(in1.map { $0.dimensions }) }
                    if !tabWindows.isEmpty { trial.lineIndents = tabWindows }
                    trial.layout(minWidth: textWidth, maxWidth: textWidth)
                    let found = Array(_lineStarts(trial, _OffsetMap(lead: lead != 0 ? 1 : 0, inserts: ins1), count: units.count).dropFirst())
                    trial.dispose()

                    if found == wraps { break }
                    wraps = found
                    measure(wraps)
                }
                // (A justified line stretches only what follows its last
                // tab, where anything does: zh-6a4fc013's "คำถามที่  2 ：<tab>
                // การเปิดนำเข้า…", the Thai after the tab with no space in it,
                // ends short of the margin in Word's print with its two
                // spaces as they are; ours stretched them and set "2 ：" 30pt
                // on. A line the tab ends is stretched as any — its "คำถามที่
                // 3 ：<tab>", the Thai on the next line.)
                if theme.wordRules, style.alignment == .justify {
                    let starts = [0] + wraps
                    for (n, from) in starts.enumerated() where n + 1 < starts.count {
                        let to = starts[n + 1]
                        guard let t = (from ..< to).last(where: { units[$0] == 0x09 }),
                              (t + 1 ..< to).contains(where: { units[$0] != 0x20 && units[$0] != 0x09 }) else { continue }
                        beforeTabs.formUnion((from ..< t).filter { units[$0] == 0x20 })
                    }
                }
            }
            probe.dispose()
        }
        }
        _blk3()
        // (In a justified paragraph each such tab is set as a held
        // space — a no-break one, the break after it a zero-width space:
        // the engine's justifying sets every space of a line, tabs
        // included, to its one step, and the widening was lost. Lab `tj`,
        // Word for Windows: "1.1.<tab>" with a stop at 1418 twips starts
        // its text at the stop justified or not; ours, justified, 15pt
        // short — bug65649's every numbered clause.)
        // (A slide paragraph that opens with a tab: the tab's widening goes
        // into the first line's indent box instead. The engine sets a
        // character's added spacing half before it, and at the start of a
        // line that moved the whole line on — HowWeRefactor's quotes
        // started 10.8pt right of their indent. A document's the same:
        // WordWithAttachments' header, "<tab>Страница 1" on a centre stop,
        // stood half its tab — 101pt — right of Word's.)
        var leadTab = false
        if theme.markersAtHang || theme.wordRules, p.text.utf16.first == 0x09, let e = tabs[0], e != 0 {
            lead += e
            tabs[0] = nil
            _leadWidth[i] = lead
            leadTab = true
        }
        // (Not one set at the margin: it ends its line, which is not
        // justified after it, and a held space is a little wider than
        // the tab it stands for — enough, at the margin, to send the
        // page number to a line of its own. Lab `tb`'s justified "toc 1"
        // entry did; set left, it did not.)
        // (And underlined spaces where the document underlines them at a
        // line's end, `w:ulTrailSpace`: text there, they hang past no
        // margin, and a run of them stays with what stands before it.
        // zh-f47b8a74's notices leave blanks of underlined spaces —
        // "…号），因" and 105 of them, 8pt apiece — and Word's print sets
        // "因" and 53 on a line of their own, the other 52 and "，根" on the
        // next; ours kept "因" on the line before, the run hanging past
        // its margin, and every line after stood one early. Not the
        // paragraph's closing spaces: `_looseWordOffsets` has those.)
        // (Only a run that, with the character before it, is wider than
        // the line: one that fits hangs past the margin as any spaces do —
        // zh-621d8756's "申请人：" and 48 underlined spaces, then "申请项目："
        // in the same paragraph, run 32pt past the margin in Word's print
        // and "申请项目：" opens the next line.)
        var underHeld: Set<Int> = []
        if theme.wordRules, document.underlinesTrailingSpaces, p.text.utf16.contains(0x20) {
            let units = Array(p.text.utf16)
            var closing = units.count
            while closing > 0, units[closing - 1] == 0x20 { closing -= 1 }
            var at = 0
            for run in p.runs {
                defer { at += run.length }
                guard run.style.underline, run.style.inlineImage == nil, at < closing else { continue }
                let size = run.style.fontSize ?? _named(p, document)?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                let space = document.balancesSpaceWidth ? size / 2 : size / 4
                var k = at
                let stop = min(at + run.length, closing)
                while k < stop {
                    guard units[k] == 0x20 else { k += 1; continue }
                    var end = k
                    while end < stop, units[end] == 0x20 { end += 1 }
                    let before = k > 0 && units[k - 1] != 0x20 ? size : 0
                    // (And one a closing mark follows, which may not open a
                    // line: zh-f47b8a74's "…将罚款缴至", 19 underlined spaces
                    // and "，账号" go down whole in Word's print, "至" opening
                    // the line; hanging, ours began the next with the "，".)
                    let closed = end < units.count && Unicode.Scalar(units[end]).map { Self._closingMarks.contains(Character($0)) } == true
                        && document.usesEastAsianLayout && p.style.eastAsian["w:kinsoku"] != "0"
                    if _px(Double(end - k) * space + before) > textWidth || closed { underHeld.formUnion(k ..< end) }
                    k = end
                }
            }
        }
        // (A run of tabs in Word for Windows does not hang past the margin as spaces do: each
        // goes to the next line when its stop is past the margin, and the stops start again
        // there — tdf92157's signature block, 9 and 23 tabs, "Zaken," five stops in on the
        // third line; ours let them all hang and set the text at the margin's start.)
        let tabRuns: Set<Int> = theme.wordRules && RichTextTheme.wordWindowsPages
            ? Set(tabs.keys.filter { t in (t > 0 && p.text.utf16[p.text.utf16.index(p.text.utf16.startIndex, offsetBy: t - 1)] == 0x09) || (t + 1 < p.text.utf16.count && p.text.utf16[p.text.utf16.index(p.text.utf16.startIndex, offsetBy: t + 1)] == 0x09) }).subtracting(atMargin)
            : []
        if !tabRuns.isEmpty { RuleTrace.hit("tab-runs-do-not-hang-past-the-margin") }
        let tabsHeld: Set<Int> = (theme.wordRules && style.alignment == .justify ? Set(tabs.keys).subtracting(atMargin) : []).union(leadTab && theme.wordRules && style.alignment == .justify ? [0] : []).union(underHeld).union(beforeTabs).union(tabRuns).union(lonePastTabs).union(afterTabWraps)
            .union(theme.wordRules && RichTextTheme.wordWindowsPages ? Self._underlinedClosingCounted(p) : [])
        // A line exactly as wide as its room fits or not as Word's sum of
        // the room comes out: each measure in twips goes to the sixteenth
        // of a point (1.25 twips; the left and hanging indents to the
        // nearest, a right outdent's size cut down) and the
        // measures are added — the column, less the left indent, plus the
        // hanging one, less the right. Where that lands under the room's
        // true width, the line that needs all of it does not fit. Labs f39
        // and f39b (Word for Windows, zh-f39e54b6's package, 200 prints):
        // 第十四條, 第十五條, 第二十四條 and 三、… need 441.0pt exactly, their
        // two commas squeezed to half; the next character is taken if and
        // only if left mod 5 twips is 3 or 4 (hanging = left + 108, right
        // -108), at any left from 1000 to 2180, and from right -109 at the
        // others — which the sixteenth-point sum gives and no sum in
        // doubles does. Word for Mac's print refuses 第十四條's the same
        // way. The painter's slack takes the verdict, and so does
        // `_fitEastAsianLines`, whose `hair` and `edge` would otherwise
        // take such a line.
        // (One 600 dpi grid step, 0.12 pt, past the room, in a paragraph with Devanagari: Word places glyph
        // origins on that grid and takes a line whose end lands one step past the edge (Hindi and Nepali
        // prints, amd-1 2026-11-15). Latin and Cyrillic text does NOT get it: dx2 A/B, 60 Latin-script docs
        // fell, e.g. kk 61bba885 100 to 36.5. Ideographs, kana and Hangul keep the thousandth.)
        var tieSlack = p.text.unicodeScalars.contains { $0.value >= 0x900 && $0.value <= 0x97F } && !p.text.unicodeScalars.contains { $0.value >= 0x2E80 } ? 0.12 : 0.001
        var tieShort = (first: false, rest: false)
        @inline(never) func _q3() {
        if theme.wordRules, wordList == nil, style.list == nil, !style.rightToLeft {
            let tw = { (px: Double) -> Int in Int((px / self._px(1) * 20).rounded()) }
            let w = tw(textWidth + ownLeft + right), l = tw(ownLeft), r = tw(right), h = -tw(lead)
            // (A first-line indent is a negative hanging one, and is cut down
            // like a right outdent: zh-4a2ab598's "无", twelve points in
            // a cell room of 722 twips less a first line of 482, is on
            // Word's first line.)
            // (The sixteenth-point sum is the lab's, on ideographs and
            // their marks alone: a tab stop, a character grid or a Latin
            // letter or digit on the line has widths the sum here is not
            // Word's to the thousandth on, and keeps the earlier sum in
            // points — which only a line that is a hair short of its room
            // by the indents' own rounding refuses. The column is taken as
            // it is, not quantised: with it quantised too, zh-73534289's
            // cells (auto width, no indent) lost a character a line.)
            let latin = p.text.unicodeScalars.contains { $0.value < 0x2E80 && !$0.properties.isWhitespace }
            let labSum = !p.text.unicodeScalars.contains("\t") && (_grid(i, document).chars ?? 0) == 0 && !latin
            let sixteenth = { (t: Int) -> Double in labSum ? (Double(t) / 1.25).rounded() * 1.25 : Double(t) / 20 }
            let outdent = { (t: Int) -> Double in labSum ? (t < 0 ? (Double(t) / 1.25).rounded(.up) * 1.25 : sixteenth(t)) : Double(t) / 20 }
            let eps = labSum ? 1e-6 : 0
            let unit = labSum ? 1.0 : 20.0
            let column = labSum ? Double(w) : Double(w) / 20
            let rest = column - sixteenth(l) - outdent(r)
            // (With a Latin letter or digit in text whose characters are spaced out, a line exactly
            // as wide as its room does not fit: zh-447f1d5c's p57, "依据《…》（GB/T14885-2010）标准编码"
            // and its 的, 20 ideographs at 16.3pt and 14 Latin at 8.3 in a room of 442.2, keeps the
            // 的 in Word's print only with the right indent at -1 twip (amd-perf's lab p57).)
            let named = _named(p, document)?.char.letterSpacing ?? _normalChar(document)?.letterSpacing ?? 0
            let latinTie = latin && !p.text.unicodeScalars.contains("\t") && (_grid(i, document).chars ?? 0) == 0
                && p.runs.contains { ($0.style.letterSpacing ?? named) > 0.0001 }
            tieShort.rest = rest < Double(w - l - r) / unit - eps || latinTie
            tieShort.first = tieShort.rest
            if tieShort.rest { tieSlack = -0.0005 }
            if lead != 0 {
                let first = column - sixteenth(l) + outdent(h) - outdent(r)
                tieShort.first = first < Double(w - l + h - r) / unit - eps || latinTie
                // (A Devanagari paragraph's 0.12 pt grid step is the first line's too: the box was set 0.119 pt in,
                // which drew its origin there (xd 6be5dbc9 p3 "ज." at 108.12 where Word prints 108.02) and left the
                // line no step past the edge, so "अनधिकृत" ending 0.05 past it went to the next line.)
                let firstSlack = tieShort.first ? -0.0005 : (tieSlack > 0.1 ? tieSlack : 0.001)
                // (The first line's room is the painter's width less its
                // indent box: the box takes what the other lines' slack
                // gives the first line beyond its own.)
                lead += _px(tieSlack - firstSlack)
                _leadWidth[i] = lead
            }
        }
        }
        _q3()
        // (Beside a float: the lines that stand level with it are held in too.
        // Laid out once as they fall, the lines the float reaches get an
        // indent each, and laid again until they settle.)
        var besideLineIndents: [LineIndent] = []
        var equationLinesGrowAfterLayout = false
        var besideIndent = _besideLead[i]
        var besideRight = besideIndent > 0 && _besideRightSide[i]
        var besideLeftRoom: Double?
        var besideBand = besideIndent > 0 ? _besideBand(i, document) : nil
        var colWrapBoxes = _colWrap[i]
        if let boxes = colWrapBoxes, besideIndent == 0, !boxes.isEmpty { besideIndent = 1; besideBand = (-1, -1) }
        else
        if besideIndent > 0, besideBand == nil { _besidePending.insert(i) }
        else if besideIndent == 0, let own = _besideOwn(i, p, document) { besideIndent = own.indent; besideBand = own.band; besideRight = own.right; besideLeftRoom = own.leftRoom
            if colWrapBoxes == nil, besideLeftRoom == nil, !besideRight, let seq = _besideSeq[i] { colWrapBoxes = seq; besideIndent = 1; besideBand = (-1, -1); RuleTrace.hit("word-boxes-one-under-the-other-hold-lines-by-their-own-edge") } }
        else if besideIndent == 0, let own = _stripUse[i] { besideIndent = own.indent; besideBand = own.band; besideRight = own.right }
        if let cap = _bandCap[i], besideIndent > 0, besideLeftRoom == nil, let b = besideBand, b.bottom > cap { besideBand = (b.top, cap) }
        @inline(never) func _blk4() {
        if besideIndent > 0, let band = besideBand {
            // (The painter's own per-line indents hold the lines in: no boxes
            // at line starts, and no offsets to map.)
            let original = _px(firstLineIndent(p, at: i, document))
            // (A list item's first line beside a box at the left sets its number and its
            // text past the box's edge by their own offsets, the lines under it at the
            // edge or their indent, whichever is further: lo
            // tdf109308_dropCapNumbered, "1." at 139.3 and the text at 157.3 in Word's
            // print, the two lines under it at 121.3 and the last at 108.)
            var firstExtra = 0.0
            // (The first-line indent counts from the picture's edge when the picture stands at the top margin
            // and out past the left one: Word's print of xd 658a33bb, "참가신청서" 60pt in from the edge.)
            if _besideIndentOnTop.contains(i), !besideRight, besideLeftRoom == nil, original > 0 { firstExtra = original }
            else
            if theme.wordRules, RichTextTheme.wordWindowsPages, !besideRight, besideLeftRoom == nil, p.cell == nil, p.style.list == nil, p.style.listId == nil,
               original < 0, p.style.indentLeft > 0, (document.compatibilityMode ?? 12) < 15 {
                // (Compat 14, a hanging item (typed bullet and tab) beside a picture: Word's print of lab pic-wrap sets the bullet 18pt and the
                // text 36pt in from the picture's edge, its own offsets, the lines under it at the edge.)
                firstExtra = _px(p.style.indentLeft) + original
                RuleTrace.hit("word-c14-hanging-item-beside-picture-keeps-its-offsets")
            }
            else
            if theme.wordRules, RichTextTheme.wordWindowsPages, !besideRight, _besideLead[i] == 0, p.cell == nil, !_besideListEarlier.contains(i),
               p.style.listId != nil, let own = _listIndents(p, document), own.left > 0 {
                firstExtra = _px(own.left)
                RuleTrace.hit("word-list-first-line-beside-box-is-past-the-edge")
            }
            _besideLabelShift[i] = nil
            var indents: [LineIndent] = []
            var firstBeside = true
            var firstLead: Double? = nil
            for _ in 0 ..< (besideLeftRoom != nil ? 24 : 8) {
                let (trialSpan, _, _) = _span(for: p, at: i, document, textWidth: textWidth, lead: firstBeside && !besideRight && besideLeftRoom == nil ? max(original - besideIndent, 0) : firstLead ?? original,
                                              adjust: hangs.isEmpty ? tabs : tabs.merging(hangs) { $0 + $1 }, held: tabsHeld)
                let trialInline = _span(for: p, at: i, document, textWidth: textWidth, lead: firstLead ?? original, adjust: hangs.isEmpty ? tabs : tabs.merging(hangs) { $0 + $1 }, held: tabsHeld).1
                let trial = TextPainter(text: trialSpan, textAlign: .left, textDirection: .ltr)
                if !trialInline.isEmpty { trial.setPlaceholderDimensions(trialInline.map { $0.dimensions }) }
                trial.lineIndents = indents
                trial.layout(minWidth: 0, maxWidth: textWidth)
                var bottoms = Self._lineBottoms(trial)
                // (Both sides of a box: a row takes a left piece only when the next word fits the room at the box's left, as Word's
                // print of lab wg1 does, a left strip first holding text at 21pt, where "[30]" (19.6pt) fits, and not at 18pt.)
                let leftFits: [Bool] = besideLeftRoom != nil && (_besideBoxes[i]?.count ?? 0) < 2 && (colWrapBoxes?.isEmpty ?? true)
                    ? Self._nextWordFits(trial, trialSpan, room: besideLeftRoom ?? 0) : []
                trial.dispose()
                // (Lines of Arabic-script text are tested at the height they are set at: lo tdf163575's 12pt
                // lines come out 15.9pt of the fallback face here and are set 13.8, and the third line above a
                // picture, at 41.4 over its top at 43, was held in by it at 47.7.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.rightToLeft, p.style.lineHeightPoints == nil,
                   let nat = theme.naturalLine(for: p.runs[0].style, named: _named(p, document), eastAsian: false).map({ _px($0) }),
                   let h0 = bottoms.first, h0 > nat + 0.5, bottoms.indices.allSatisfy({ abs(bottoms[$0] - Double($0 + 1) * h0) < 1 }) {
                    bottoms = bottoms.indices.map { Double($0 + 1) * nat }
                }
                var next: [LineIndent] = []
                if let boxes = colWrapBoxes, !boxes.isEmpty, besideLeftRoom == nil, _besideLead[i] == 0 {
                    for k in 0 ..< bottoms.count {
                        let top = k == 0 ? 0 : bottoms[k - 1]
                        if let b = boxes.first(where: { $0.byStart ? (top >= $0.top - 0.01 && top < $0.bottom - 0.01) : (bottoms[k] > $0.top + 0.01 && top < $0.bottom - 0.01) }) {
                            var right = b.right
                            if !b.outline.isEmpty, b.left == 0, b.outH > 0, let m = Self._outlineMinX(b.outline, (top - b.outTop) / b.outH, (bottoms[k] - b.outTop) / b.outH) {
                                right = max(b.outBase - (b.outX + b.outW * m - b.outGap), 0); RuleTrace.hit("word-tight-wrap-line-meets-the-outline-over-its-own-rows")
                            }
                            next.append(LineIndent(left: b.left, right: right))
                        } else { next.append(LineIndent()) }
                    }
                } else if besideLeftRoom != nil, let boxes = _besideBoxes[i], boxes.count >= 2 {
                    // (Round two boxes or more: a row of the page is the room
                    // left of the first, between them, and right of the last,
                    // each a line of the painter, the later ones lifted level
                    // with the first by `_registerPairs`. Word's print of
                    // lo-6e93e16d: a tight object and a square one.)
                    let minRoom = _px(p.runs.first?.style.fontSize ?? theme.fontSize) * 2
                    var saved = 0.0, k = 0
                    while k < bottoms.count {
                        let before = k == 0 ? 0 : bottoms[k - 1]
                        // (Lines carried past a picture stand where the jump puts them: see `_lineDrop`.)
                        let drop = _lineDrop[i].flatMap { k >= $0.from && $0.from >= 1 && $0.from <= bottoms.count ? $0.dy - bottoms[$0.from - 1] : nil } ?? 0
                        let top = before - saved + drop, bottom = bottoms[k] - saved + drop
                        let active = boxes.filter { bottom > $0.top + 0.01 && top < $0.bottom - 0.01 }.sorted { $0.left < $1.left }
                        var segments: [(from: Double, to: Double)] = []
                        // (The first line of a hanging paragraph starts in the hanging area, and its first piece with it.)
                        let hang = k == 0 ? max(0, -original) : 0
                        var x0 = -hang
                        for b in active {
                            if b.left - x0 >= minRoom { segments.append((x0, b.left)) }
                            x0 = max(x0, b.right)
                        }
                        if !active.isEmpty, textWidth - x0 >= minRoom { segments.append((x0, textWidth)) }
                        if active.isEmpty || segments.isEmpty { next.append(LineIndent()); k += 1; continue }
                        for (j, seg) in segments.enumerated() where k + j < bottoms.count {
                            if k == 0, j == 0, hang > 0, seg.from < 0 {
                                // (The first piece starts in the hanging area: the line is laid from the margin to its end, the lead
                                // taking it back to the piece's start, so the painter's width stays positive.)
                                firstLead = 0
                                next.append(LineIndent(left: seg.from, right: max(textWidth - seg.to, 0)))
                            } else {
                                next.append(LineIndent(left: max(seg.from, 0), right: max(textWidth - seg.to, 0)))
                            }
                            if j > 0 { saved += min(bottoms[k + j] - bottoms[k + j - 1], bottoms[k] - before) }
                        }
                        k += segments.count
                    }
                } else if let leftRoom = besideLeftRoom {
                    // (Both sides: a line level with the box is the left piece, in
                    // the room at its left, and the line after it the right
                    // piece, level with it. The lines after the pair stand where
                    // they would if the right piece took no room: `saved` is the
                    // height the right pieces give back.)
                    var saved = 0.0, k = 0
                    while k < bottoms.count {
                        let before = k == 0 ? 0 : bottoms[k - 1]
                        if bottoms[k] - saved > band.top + 0.01, before - saved < band.bottom - 0.01, k < leftFits.count, !leftFits[k] {
                            // (No word fits the strip: the row is the right piece alone. Its 0.001 right inset keeps `_registerPairs`
                            // from taking it for the right piece of a pair.)
                            next.append(LineIndent(left: besideIndent, right: 0.001)); k += 1
                        } else if bottoms[k] - saved > band.top + 0.01, before - saved < band.bottom - 0.01 {
                            next.append(LineIndent(left: 0, right: max(textWidth - (_besideLeftAt[i]?(before - saved, bottoms[k] - saved) ?? leftRoom), 0)))
                            if k + 1 < bottoms.count {
                                next.append(LineIndent(left: _besideStartAt[i]?(before - saved, bottoms[k] - saved) ?? besideIndent, right: 0))
                                saved += min(bottoms[k + 1] - bottoms[k], bottoms[k] - before)
                            }
                            k += 2
                        } else {
                            next.append(LineIndent()); k += 1
                        }
                    }
                } else {
                    // (A line of "at least" height is tested by its text's own extent — its leading stands above the
                    // text and takes no room from a box above it: lo-717ff943's 10pt lines at 18.65pt, whose
                    // baseline 13.5 under a picture's foot Word's print sets across the page, as it does a line level with its
                    // top; ours narrowed it to the picture's width for the leading.)
                    let textLine: Double? = theme.wordRules && RichTextTheme.wordWindowsPages && p.style.lineHeightPoints != nil && p.style.lineHeightIsMinimum
                        ? theme.naturalLine(for: p.runs[0].style, named: _named(p, document), eastAsian: false).map { _px($0) } : nil
                    for k in 0 ..< bottoms.count {
                        var top = k == 0 ? 0 : bottoms[k - 1]
                        if let textLine { top = max(top, bottoms[k] - textLine) }
                        // (Lines carried past a picture stand where the jump puts them: see `_lineDrop`.)
                        let drop = _lineDrop[i].flatMap { k >= $0.from && $0.from >= 1 && $0.from <= bottoms.count ? $0.dy - bottoms[$0.from - 1] : nil } ?? 0
                        let beside = (bottoms[k] + drop > band.top + 0.01 && top + drop < band.bottom - 0.01)
                            || (_besideMoreBands[i] ?? []).contains { bottoms[k] + drop > $0.top + _px(3) && top + drop < $0.bottom - _px(3) }
                        // (The beside-box indent counts from the column's edge, not from the width cut to whole
                        // cells: efbb06c2's lines beside a picture hold 22 characters of 11 in Word's print,
                        // 246.2 of room, where the cut column less the indent held 21.)
                        // (A box at the line's start as well as the one at the right: the lines level with each stand in the window between them, as Word's print of lab ellhdr, a 2pt tab line between two header boxes.)
                        let startLeft: Double = besideRight ? (_besideStartLeft[i].flatMap { sl in bottoms[k] > sl.band.top + 0.01 && top < sl.band.bottom - 0.01 ? sl.indent : nil } ?? 0) : 0
                        next.append(besideRight ? LineIndent(left: startLeft, right: beside ? max((_besideRightAt[i]?(top, bottoms[k]) ?? besideIndent) - gridCut, 0) : 0) : LineIndent(left: beside ? besideIndent + (k == 0 ? firstExtra : 0) : 0, right: 0))
                    }
                }
                while let last = next.last, last.left == 0, last.right == 0, next.count > 1, next[next.count - 2].left == 0, next[next.count - 2].right == 0 { next.removeLast() }
                let first = next.first.map { $0.left > 0 || $0.right > 0 } ?? false
                if next == indents, first == firstBeside { break }
                indents = next
                firstBeside = first
            }
            if indents.contains(where: { $0.left > 0 || $0.right > 0 }), indents.last.map({ $0.left != 0 || $0.right != 0 }) == true { indents.append(LineIndent()) }
            besideLineIndents = indents
                // (A list item beside a box at the right no longer keeps its label's box: that rule, fit
                // to lo-717ff943's earlier print, left each bullet 1.5pt under the label-less line in
                // the Windows print, which has bullet and text on one baseline.)
                if !firstBeside || besideRight || besideLeftRoom != nil || (!(colWrapBoxes?.isEmpty ?? true) && (indents.first?.left ?? 0) == 0) { lead = firstLead ?? original; _leadWidth[i] = lead }
            else { lead = max(lead - besideIndent - firstExtra, 0); _leadWidth[i] = lead }
            if firstExtra > 0, firstBeside, let f = indents.first, f.left > 0 { _besideLabelShift[i] = f.left }
            else if _besideListEarlier.contains(i), firstBeside, let f = indents.first, f.left > 0 { _besideLabelShift[i] = f.left }
        }
        }

        _blk4()
        if theme.wordRules, RichTextTheme.wordWindowsPages, !tabs.isEmpty, tabWindows.isEmpty, besideRight, besideLeftRoom == nil,
           besideLineIndents.contains(where: { $0.left > 0 }), besideLineIndents.contains(where: { $0.right > 0 }) {
            tabWindows = besideLineIndents
            _blk3()
            _blk4()
        }
        // (Tabs beside a box at the left: the line starts at the box's edge, but the default stops stay on the margin's grid, the
        // first tab short — sa1 7f30fc29's cover, Word 6 tabs a line beside box 1 where ours had 5 from the edge.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, !tabs.isEmpty, tabWindows.isEmpty, !besideRight, besideLeftRoom == nil,
           besideLineIndents.contains(where: { $0.left > 0 }) {
            tabWindows = besideLineIndents
            _blk3()
            _blk4()
        }
        let (span, inline, inserts) = _span(for: p, at: i, document, textWidth: textWidth, lead: lead,

                                            adjust: hangs.isEmpty ? tabs : tabs.merging(hangs) { $0 + $1 }, held: tabsHeld)
        _inserts[i] = inserts
        // A right-to-left paragraph runs from the right, and its "left"
        // (Word's start) is the right edge.
        var align = Self._textAlign(style.alignment)
        // (jc thaiDistribute, Word's print of lab thd1: a line broken at a space is set out to the full width by room between its
        // letters, the spaces taking the same share as a letter and none of their own; the engine's justify, which widens only
        // the spaces, is off for it — `_thaiDistribute` below spreads the lines.)
        // (Compatibility 15 files print it as plain justify: 10ffb69f, a3710694, c929c653, 75eee205 fell when spread, and the
        // files below 15, or naming none, rose: 46490205 50 to 55, e93587db 82 to 86, 93962bba 96 to 100.)
        let thaiDistributed = theme.wordRules && RichTextTheme.wordWindowsPages && style.alignment == .justify
            && (document.compatibilityMode ?? 0) < 15
            && style.eastAsian["w:jc"] == "thaiDistribute" && !style.rightToLeft
            && p.text.unicodeScalars.contains(where: { (0x0E01 ... 0x0E5B).contains($0.value) })
        if thaiDistributed { align = .left }
        if style.rightToLeft {
            switch style.alignment {
            case .left: align = .right
            case .right: align = .left
            default: break
            }
        }
        // A floating frame of no stated width is as wide as its text, so
        // set right or centred in its band the text stands there: laid
        // over the whole band, it is aligned so. (Bug51170's footer page
        // number, a frame aligned right in the margins, stood at their
        // left on every page.)
        if frameLeft != nil, let frame = style.frame, frame.width == nil {
            switch frame.horizontalAlign == "outside" ? (leftHandPage ? "left" : "right") : frame.horizontalAlign == "inside" ? (leftHandPage ? "right" : "left") : frame.horizontalAlign {
            case "right": align = .right
            case "center": align = .center
            default: break
            }
        }
        // (A picture in the line makes its own line taller — not a
        // horizontal rule, whose line is its text's: the reader's "hr";
        // nor a floating object that takes no room in it, only its
        // anchor: zh-a7728bc9's title, after the anchor of a text box,
        // stood 4.2pt low of Word's with its line left to the engine.)
        let picturesInLine = inline.contains { entry in
            guard let image = entry.image else { return false }
            return image.name != "hr" && !(theme.wordRules && image.float.map { !$0.takesRoom } == true)
        }
        // (A bold run beside its regular text sets the line Word gives the
        // regular where the paragraph is spaced well over single (1.5 lines
        // in zh-86547e97 and zh-d746674a) — see `_strut`.
        // At single spacing each line keeps its tallest: bug59058's Times
        // paragraphs, bold labels in their lines, stand a hair apart line by
        // line in Word's print as in the engine's.)
        // (… and in a document of East Asian layout at single spacing
        // too, where a Latin stretch is drawn by its East Asian face's
        // stand-in: the stand-in splits the line about its baseline its
        // own way, and the line it shares grew a point — zh-ae2dd08d's
        // "(一) 一般對象（補助80%…" first line, beside a bold YaHei run
        // lower down, stood 21.5pt where Word's is 20.4.)
        let spacedOver = theme.wordRules && style.lineHeightPoints == nil
            && (style.lineSpacing > 1.2 || document.usesEastAsianLayout)
        // (A Thai paragraph too, its bold's hair-taller line held with the regular (`_sameLine` wide): its stand-in is drawn at 0.82 of the
        // size and, with no strut, the faces stacked 2.5 pt over: dx2 3f86ce1b's "ข้อ 1." lines, 24.6 apart for Word's 22.0.)
        let thaiNear = theme.wordRules && style.lineHeightPoints == nil && p.text.unicodeScalars.contains(where: { (0x0E01 ... 0x0E5B).contains($0.value) })
        // (A larger number's height over the first line, where the
        // paragraph keeps its strut: see `laidOut`.)
        var numberLift = 0.0
        func lines1(_ t: TextPainter) -> Bool { t.computeLineMetrics().count == 1 }
        func laidOut(_ span: TextSpan) -> TextPainter {
            let rises = Self._risesForNumber(inline)
            numberLift = 0
            // (A number larger than its text lifts the first line alone;
            // every line keeps the paragraph's strut, and the first is set
            // as much lower as the number's box takes it. zh-7773163d's
            // "●案例" headings, 18pt text under a 20pt bullet at 1.3 lines,
            // stand 27.3pt apart after the first in Word's print, as
            // without the bullet; with the strut dropped for the box, every
            // line was the fallback face's own, 29.1. The engine's forced
            // strut does not see the box, so its lift is measured from a
            // layout without the strut.)
            // (A picture in a line makes that line its own height, and a held strut
            // would take it down to the text's: kept, in a right-to-left paragraph of Word's
            // Windows print, where the pictures stand in the first line, which is then lifted
            // as the picture's height takes it — see below. lo-7ec36a70's rows of Persian, 13.8pt
            // in Word's print, were 16.2 in the fallback face's own height, a 43pt picture
            // opening one of them.)
            // (An equation that stands after the first line leaves that line the paragraph's own: Word's
            // print of jpn-z22855378-6fca0f puts a 1.5-line paragraph's first line 41.1pt under the last,
            // as without the equation; with the strut dropped for the equation's box, 45.2. A paragraph
            // with an equation in its first line, or of one line, is as before.)
            var pil = picturesInLine
            // (Where the line-growing step after layout runs, the paragraph keeps its strut and that step sizes the taller equation lines.)
            equationLinesGrowAfterLayout = theme.wordRules && RichTextTheme.wordWindowsPages && p.cell == nil && !style.rightToLeft && _columns <= 1
                && style.lineSpacing > 0.999 && style.lineHeightPoints == nil && besideLineIndents.isEmpty
            if pil, theme.wordRules, RichTextTheme.wordWindowsPages, !style.rightToLeft,
               inline.allSatisfy({ $0.image.map { $0.name == "m:oMath" && $0.float == nil } ?? true }),
               (equationLinesGrowAfterLayout || _equationsAfterFirstLine(span, inline.map { $0.dimensions }, align: align, rtl: style.rightToLeft, width: textWidth + _px(tieSlack), indents: besideLineIndents)
                // (Equations in the first line too, none of them taller than the strut's own line: Word's print of the same
                // paragraph puts its first line 41.0 under the heading above, as without the equations (a and l_p in the first
                // line, 45.2 with the strut dropped for their boxes).)
                || _equationsWithinStrut(span, inline.map { $0.dimensions }, whole: inline.map { _px(($0.image?.naturalExtent?.ascent ?? 0) + ($0.image?.naturalExtent?.descent ?? 0)) }, near: spacedOver || thaiNear, wide: thaiNear, multiple: style.lineSpacing)) {
                RuleTrace.hit("word-equations-after-the-first-line-keep-the-paragraphs-strut")
                pil = false
            }
            let strut = pil ? nil : _strut(span, near: spacedOver || thaiNear, wide: thaiNear)
            let painter = TextPainter(
                text: span,
                textAlign: align,
                textDirection: style.rightToLeft ? .rtl : .ltr,
                strutStyle: strut
            )
            // (Word's lines keep the fraction of their height: a 12pt
            // PMingLiU line is 15.61pt, 1332/1024 em, and zh-de3410bd's
            // page 1 ends where Word's does only with it — rounded to
            // 15.6, its last two lines fit with 0.35pt to spare where
            // Word's print takes them to page 2.)
            painter.fractionalLineHeights = theme.wordRules
            painter.lineIndents = besideLineIndents
            if !inline.isEmpty { painter.setPlaceholderDimensions(inline.map { $0.dimensions }) }
            // (A thousandth of a point over: a line that is exactly the
            // column's width — ten ideographs in ten ems — must fit, and
            // the sum of its advances may come out a hair above. No
            // more: zh-ae655121's "(F)＝(D)－(E)", YaHei's widths at
            // 14pt, is 81.8535pt in a cell of 81.85, and Word puts "(E)"
            // on a line of its own; at five thousandths it stayed.)
            // (Less, where Word's sum of the room falls short of it: see
            // `tieSlack`.)
            let slack = theme.wordRules ? _px(tieSlack) : 0
            // (A paragraph of pictures, spaces and breaks with a picture
            // wider than the line is laid out as wide as that picture: the
            // engine sets such a picture alone on its line and loses the
            // break after it, and the line that break opens — lab `ps`, a
            // 76pt picture, a `w:br` and a space in a cell of 74.35pt, is
            // one line in ours and two in Word's. Word keeps the picture
            // at the line's left, as it stands here.)
            var lineWidth = textWidth
            if theme.wordRules,
               let widest = inline.compactMap({ $0.image == nil ? nil : $0.dimensions.size.width }).max(), widest > textWidth,
               p.text.unicodeScalars.allSatisfy({ [0xFFFC, 0x20, 0x0A, 0x0B, 0x2028].contains($0.value) }) {
                lineWidth = widest
            }
            // (A line too narrow for one character is laid out one
            // character wide, every character a line — see `_span`: over
            // its width the engine keeps "6分" on one line, a break
            // between them or not.)
            if theme.wordRules, !p.text.isEmpty {
                let em = _px(p.runs.first?.style.fontSize ?? _named(p, document)?.char.fontSize ?? theme.fontSize)
                if textWidth < em {
                    // Word sets a line narrower than a glyph one character wide, whatever the
                    // glyph (colindent labs: Times 'm' and 'i' alike stack one a line); a CJK
                    // character is the em wide and the floor below keeps it.
                    let latin = p.cell == nil && left > 0 && textWidth <= 1.01 && p.text.unicodeScalars.allSatisfy { $0.value < 0x0250 }
                    lineWidth = latin ? max(lineWidth, 1) : max(lineWidth, em)
                }
            }
            // (Word holds a reserve back from the fit of a line set `mediumKashida` or
            // `highKashida` and justifies across the whole width: its lab (tdf155707, Calibri 11,
            // "word" x150) fits 15 / 15 / 14 words at 453.6 / 433.6 / 413.6pt where `both` fits
            // 17 / 17 / 16 and the full lines still end at the margin; high 14 / 13. The reserve is
            // about 0.105 of the width for medium, 0.19 for high; low fits as `both`.)
            if theme.wordRules, style.alignment == .justify {
                switch style.eastAsian["w:jc"] {
                case "mediumKashida": painter.fitReserve = 0.10 * lineWidth
                case "highKashida": painter.fitReserve = 0.20 * lineWidth
                default: break
                }
            }
            painter.layout(minWidth: lineWidth + slack, maxWidth: lineWidth + slack)
            // (A paragraph of spaces alone is one line, its spaces hung
            // past the edge as a line's last ones are: zh-cfb32050's form
            // opens with a 14pt cell holding fifteen spaces under a
            // 31-character first-line indent, and its row is as tall as
            // the text beside it in Word's print, 189pt; ours set the
            // spaces a line each and the row stood 216.)
            // (Not twenty or more under `w:wordWrap` off in the body, which
            // wrap as characters do: zh-621d8756's 102 are two lines of 51 in
            // Word's print, lab `trail`.)
            if theme.wordRules, !p.text.isEmpty, p.text.unicodeScalars.allSatisfy({ $0.value == 0x20 }),
               !(p.style.eastAsian["w:wordWrap"] == "0" && p.cell == nil && p.text.utf16.count >= 20),
               painter.computeLineMetrics().count > 1 {
                let whole = painter.maxIntrinsicWidth.rounded(.up) + 1
                if whole > lineWidth { painter.layout(minWidth: whole, maxWidth: whole) }
            }
            // (A first line that holds a picture keeps what a line of its text
            // alone has under its baseline: the picture stands on the
            // baseline and the text's room is under it. Lab hdr264b
            // (Word for Windows, zh-264d7516's header: a 24.3pt logo before 16pt
            // 宋体 on a 15.6pt grid): the line below the baseline is 24.5pt to the
            // next line's baseline, as the text alone's, where ours was 22.4, the
            // page's text 2.2pt high of Word's print.)
            if pil, strut == nil, theme.wordRules, RichTextTheme.wordWindowsPages, !style.rightToLeft,
               style.lineHeightPoints == nil,
               !p.text.isEmpty, p.text.unicodeScalars.contains(where: { $0.value != 0xFFFC && $0.value != 0x20 }),
               inline.allSatisfy({ $0.image.map { $0.textBox == nil && $0.name != "hr" && ($0.float == nil || $0.float.map { !$0.takesRoom } == true) } ?? true }),
               let first = painter.computeLineMetrics().first, let ref = _strut(span, near: spacedOver || thaiNear, wide: thaiNear) {
                let flat = TextPainter(text: span, textAlign: align, textDirection: style.rightToLeft ? .rtl : .ltr, strutStyle: ref)
                flat.fractionalLineHeights = painter.fractionalLineHeights
                flat.lineIndents = painter.lineIndents
                flat.setPlaceholderDimensions(inline.map {
                    PlaceholderDimensions(size: Size($0.dimensions.size.width, 0), alignment: .baseline, baseline: .alphabetic, baselineOffset: 0)
                })
                flat.layout(minWidth: lineWidth + slack, maxWidth: lineWidth + slack)
                let deficit = (flat.computeLineMetrics().first.map { $0.height - $0.baseline } ?? 0) - (first.height - first.baseline)
                let boxes = painter.inlinePlaceholderBoxes ?? []
                if deficit > 0.01, !boxes.isEmpty, boxes.allSatisfy({ $0.toRect().top < first.height - 1 }) {
                    RuleTrace.hit("word-first-line-with-a-picture-keeps-the-texts-room-under-its-baseline")
                    painter.setPlaceholderDimensions(inline.map { entry in
                        guard let image = entry.image, image.float == nil, _pageFill[image.id] == nil else { return entry.dimensions }
                        _pageFill[image.id] = entry.dimensions.size.height
                        _lineCentre[image.id] = 0
                        let d = entry.dimensions
                        return PlaceholderDimensions(size: Size(d.size.width, d.size.height + deficit), alignment: d.alignment,
                                                     baseline: d.baseline, baselineOffset: d.baselineOffset)
                    })
                    painter.layout(minWidth: lineWidth + slack, maxWidth: lineWidth + slack)
                }
                flat.dispose()
            }
            if pil, strut != nil, let first = painter.computeLineMetrics().first {
                let free = TextPainter(text: span, textAlign: align, textDirection: style.rightToLeft ? .rtl : .ltr)
                free.fractionalLineHeights = painter.fractionalLineHeights
                free.lineIndents = painter.lineIndents
                free.setPlaceholderDimensions(inline.map { $0.dimensions })
                free.layout(minWidth: painter.width, maxWidth: painter.width)
                let own = free.computeLineMetrics()
                let boxes = free.inlinePlaceholderBoxes ?? []
                if let top = own.first, own.count == painter.computeLineMetrics().count,
                   boxes.allSatisfy({ $0.toRect().top < top.height - 1 }), !rises {
                    RuleTrace.hit("word-picture-in-the-first-line-lifts-it-and-the-rest-keep-the-strut")
                    numberLift = max(0, top.baseline - first.baseline)
                    free.dispose()
                } else {
                    painter.dispose()
                    return free
                }
            } else if rises, strut != nil, let first = painter.computeLineMetrics().first {
                let free = TextPainter(text: span, textAlign: align, textDirection: style.rightToLeft ? .rtl : .ltr)
                free.fractionalLineHeights = painter.fractionalLineHeights
                free.setPlaceholderDimensions(inline.map { $0.dimensions })
                free.layout(minWidth: painter.width, maxWidth: painter.width)
                // (Not when a number set larger than its text opens a one-line paragraph at a multiple, in Word for Windows:
                // the line keeps the paragraph's strut and its extra under the text, lifted only as the number's ascent
                // asks, as the longer paragraphs do. Free of the strut it set the extra above the baseline, 1.2pt
                // too tall and the baseline 3.7pt low: Batang 9 at 1.5 lines under a 10pt Arial number, xd 03cd29dc 232 to 253
                // of 258 lines matched. A number as big as its text keeps the free line: xb jpn-z20806225.)
                // (A paragraph of one line is that line, as without the
                // strut: zh-76700e5f's "5.3 制棒" headings, 1.3pt deeper
                // held to it and lifted, set what followed that much low.)
                if painter.computeLineMetrics().count == 1, !(theme.wordRules && RichTextTheme.wordWindowsPages && style.lineHeightPoints == nil && style.lineSpacing > 1.001
                    && (_levelNumberSize(p, document) ?? 0) > (_markSize(p, document) ?? .infinity)) {
                    painter.dispose()
                    return free
                }
                // (Not by a bullet in Word for Windows, whose first baseline is the text's
                // own ascent under the line's top whatever the label: lab
                // `baseln`, and zh-7773163d's "●案例" headings, whose Wingdings
                // bullet raised it 2.4pt and stood every line after it 3pt
                // under Word's print.)
                // (A bullet too, in Word for Windows: a 16pt Arial bullet over 11pt text stands the first line on the BULLET's ascent
                // and line gap, 15.0pt, and leaves the descent the text's; items 17.4pt apart in the print of xb rus-z8098805 (4.0 to 40.0),
                // fra-g210 36.7 to 67.6. It once skipped bullets for zh-7773163d's Wingdings, whose East Asian text is the taller face.)
                // (Still not for a symbol-font bullet: zh-7773163d's Wingdings, lab `baseln`.)
                // (Nor for one set in an East Asian face, latin and East Asian alike: zh-7773163d's 20pt "●" in 細明體_HKSCS over 宋 text.)
                let bulletFonts = _levelNumberFonts(p, document)
                // (Only a bullet that sets its own size: a Thai doc's Angsana bullet with none stands where the text does in Word's print,
                // 2pt under ours when lifted; xd 53eca83a.)
                // (A Latin bullet face with no size of its own, standing higher over its baseline than the text's face (Tahoma's dash over Times,
                // sa1 508b647e): `_span` lifts the first line by the face's ascent, in a wrapped item as in a one-line one.)
                let latinRisingBullet: Bool = {
                    guard theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.list == .bullet, _levelNumberSize(p, document) == nil,
                          let fam = bulletFonts.latin?.lowercased(), !["symbol", "wingdings", "wingdings 2", "wingdings 3", "webdings"].contains(fam),
                          bulletFonts.eastAsian == nil || bulletFonts.latin != bulletFonts.eastAsian,
                          let r0 = p.runs.first else { return false }
                    let textFace = r0.style.fontFamily ?? _named(p, document)?.char.fontFamily ?? _normalChar(document)?.fontFamily
                    let pt = r0.style.fontSize ?? _named(p, document)?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                    guard let nb = theme.faceResolver?(fam, false)?.baseline, let tb = theme.faceResolver?(textFace, false)?.baseline else { return false }
                    return (nb - tb) * pt > 0.5
                }()
                let symbolBullet = p.style.list == .bullet && !latinRisingBullet
                    && (_levelNumberSize(p, document) == nil
                        || ["symbol", "wingdings", "wingdings 2", "wingdings 3", "webdings"].contains(bulletFonts.latin?.lowercased() ?? "")
                        || (bulletFonts.eastAsian != nil && bulletFonts.latin == bulletFonts.eastAsian
                            // (A Latin bullet whose rFonts name one face for both, Calibri "-": its first line stands on
                            // the bullet's ascent as any larger bullet's does; xb fra-g210-1a6d33.)
                            && !(p.style.listId.flatMap { document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.text }?
                                .unicodeScalars.allSatisfy { $0.value < 0x250 || ($0.value >= 0x2010 && $0.value <= 0x2027) } ?? false)))
                if !(RichTextTheme.wordWindowsPages && symbolBullet), let own = free.computeLineMetrics().first {
                    // (Over single spacing Word puts a line's extra under its text, so the number's
                    // baseline stands its own ascent under the line's top; the layout without the
                    // strut puts the multiple's extra above it. Measured from that baseline, a 10pt
                    // number over 9.5pt lines at 1.15 lifted the first line 1.2pt and made the
                    // paragraph as much taller, where Word's labels stand 15.4 apart:
                    // jpn-z20806225-930d98 p7's items of two Latin lines, 17.0 under the line above.)
                    var ownBaseline = own.baseline
                    if theme.wordRules, RichTextTheme.wordWindowsPages, style.lineHeightPoints == nil, style.lineSpacing > 1.001 {
                        RuleTrace.hit("word-list-number-lift-measured-with-the-extra-under-its-text")
                        ownBaseline -= (1 - 1 / style.lineSpacing) * own.ascent
                    }
                    // (A number in the text's own East Asian face, a little larger: its baseline stands higher by the face's
                    // own ratio, not by the ascent of whatever stand-in drew a glyph the substitute lacks. xb jpn-g5-b79900's
                    // 11.5pt HG Maru circled digits over 11pt HG Maru text: ours measured them on a 1.04 em stand-in and lifted
                    // each item 1.0pt, Word's print 0.5; the last line spilled onto page 2.)
                    if theme.wordRules, RichTextTheme.wordWindowsPages, let size = _levelNumberSize(p, document), let text = _markSize(p, document),
                       text > 0, size > text, let face = bulletFonts.eastAsian?.lowercased(), face == p.style.mark?.eastAsiaFontFamily?.lowercased() {
                        let scaled = first.baseline * size / text
                        if scaled < ownBaseline {
                            RuleTrace.hit("word-list-number-lift-in-the-texts-own-east-asian-face")
                            ownBaseline = scaled
                        }
                    }
                    numberLift = max(0, ownBaseline - first.baseline)
                    // (A plain-text bullet over smaller text at a line multiple: Word stands the first line on the bullet's ascent plus its
                    // external leading, unscaled by the multiple, and the text's on its own; the lift is the difference. sa1 51fd0f44's 13.5pt
                    // Times New Roman bullets over 12pt Arial Nova Light at 1.15: 0.82pt, Word's items 21.48 apart.)
                    if theme.wordRules, RichTextTheme.wordWindowsPages, style.lineHeightPoints == nil, style.lineSpacing > 1.001,
                       let bs = _levelNumberSize(p, document), let ts = _markSize(p, document), bs > ts, ts > 0,
                       let bf = bulletFonts.latin,
                       let nb = theme.faceResolver?(bf, false)?.baseline,
                       let tb = theme.faceResolver?(p.runs.first?.style.fontFamily ?? _named(p, document)?.char.fontFamily ?? _normalChar(document)?.fontFamily, false)?.baseline {
                        RuleTrace.hit("word-plain-bullet-lift-is-its-ascent-less-the-texts")
                        numberLift = max(0, nb * bs - tb * ts) * _px(1)
                    }
                    // (A character scale (w:w) over 100 is laid out as a larger size with the line's height held at the authored one, the face's
                    // extra split evenly, so the baseline of that first line stands (w - 1) x size x (its baseline in ems at height 1 - 1/2) lower
                    // than the authored size's: the lift is measured from the authored baseline. sa1 51fd0f44's w:w 105 Arial Nova Light items lifted
                    // 0.40pt for the 0.62 of the items without it, and Word's pitches are the same either way.)
                    if theme.wordRules, RichTextTheme.wordWindowsPages, let r0 = p.runs.first {
                        let named0 = _named(p, document)
                        let w = RichTextTheme.wordWidthScale(r0.style.horizontalScale ?? named0?.char.horizontalScale ?? 1, wordRules: true,
                            eastAsiaFamily: r0.style.eastAsiaFontFamily ?? named0?.char.eastAsiaFontFamily ?? r0.style.fontFamily ?? named0?.char.fontFamily ?? theme.fontFamily)
                        if w > 1.001 {
                            let ts = theme.textStyle(for: r0.style, in: style, named: named0, normal: _normalChar(document), scale: scale, fontScale: fontScale)
                            if let size = ts.fontSize, size > 0.5 {
                                let probe = ts.copyWith(fontSize: 100, letterSpacing: 0, height: 1, leadingDistribution: .even)
                                let t = TextPainter(text: TextSpan(text: "x", style: probe), textDirection: .ltr)
                                t.layout(minWidth: 0, maxWidth: 100_000)
                                if let l = t.computeLineMetrics().first {
                                    let inflate = (w - 1) * size * (l.baseline / 100 - 0.5)
                                    if inflate > 0.001 {
                                        RuleTrace.hit("word-character-scale-line-lift-measured-from-the-authored-baseline")
                                        numberLift += inflate
                                    }
                                }
                                t.dispose()
                            }
                        }
                    }
                }
                free.dispose()
            }
            if let key = Self.debugFit, !key.isEmpty, p.text.containsSubstring(key) {
                let line = "width \(i): column \(textWidth / _px(1))pt, text \(painter.maxIntrinsicWidth / _px(1))pt, \(painter.computeLineMetrics().count) lines\n"
                FileHandle.standardError.write(Data(line.utf8))
            }
            // (A line of pictures, spaces and the mark alone: Word's print sets NO text descent
            // under the pictures, whatever the size of the mark or of the spaces. A 54pt picture,
            // fifty 15pt spaces and a second picture stand with the next baseline 9.36 under their
            // bottoms, as the picture alone does; the engine gave the spaces their 15pt line
            // and the next baseline 3.2 too low (dx2 es 1c5a1268's header). Real glyphs
            // on the line keep theirs. Lab picdescent.)
            // (The same where the line also holds real text: Word's header of es 6b74a903, a 67pt picture, 11pt spaces
            // and tabs and then 8pt text, stands 0.7pt shorter than the spaces' 11pt descent makes it; with the spaces
            // and tabs set to 8pt it matches Word's print to 0.1. Only where the text is smaller than the spaces does
            // this change anything.)
            let textTail = !_inlinePictureOnly(i, document) && document.paragraphs[i].inlineImages.count == 1
            if pil, theme.wordRules, RichTextTheme.wordWindowsPages, !style.rightToLeft, _inlinePictureOnly(i, document) || textTail,
               document.paragraphs[i].text.containsSubstring(" "),
               // (Pictures, not equations, all on one line: a first line of spaces that the picture then wraps from keeps
               // its own text line — dx2 pl fa1371a3.)
               inline.allSatisfy({ $0.image.map { $0.name != "m:oMath" && $0.float == nil } ?? false }),
               painter.computeLineMetrics().count == 1 {
                func bare(_ s: InlineSpan) -> InlineSpan {
                    guard let t = s as? TextSpan else { return s }
                    var st = t.style
                    if let text = t.text, !text.isEmpty, text.allSatisfy({ $0 == " " || (textTail && $0 == "\t") }), let x = st, let size = x.fontSize, size > 0.5 {
                        st = x.copyWith(ascentOverride: 0, descentOverride: 0, height: 0.001)
                    }
                    return TextSpan(text: t.text, children: t.children?.map { bare($0) }, style: st, recognizer: t.recognizer, locale: t.locale)
                }
                let bareSpan = bare(span)
                let each = TextPainter(text: bareSpan, textAlign: align, textDirection: style.rightToLeft ? .rtl : .ltr)
                each.fractionalLineHeights = painter.fractionalLineHeights
                each.lineIndents = painter.lineIndents
                each.setPlaceholderDimensions(inline.map { $0.dimensions })
                each.layout(minWidth: textWidth + slack, maxWidth: textWidth + slack)
                if each.computeLineMetrics().count == 1 {
                    RuleTrace.hit("word-picture-and-spaces-line-has-no-text-descent")
                    // (Raised text on that line: the line is as tall as its top, the raise over the text's own ascent, where that passes the
                    // picture's foot. Word's print, sa1 a7044bb8: a 46.5 pt object and 26 pt Old English Text MT raised 23 pt stand
                    // 49.04 under the header's top, 23 + the face's win ascent 26.08, where the engine's line stood 47.75.)
                    if let m0 = each.computeLineMetrics().first, Self._paired(each) == nil {
                        var single = style; single.lineSpacing = 1
                        var grow = 0.0
                        for run in document.paragraphs[i].runs where run.length > 0 {
                            guard let r = run.style.raised, r > 0.01, run.style.script == .normal else { continue }
                            if let b = theme.baseline(for: run.style, in: single, named: _named(document.paragraphs[i], document), eastAsian: false, gridPitch: nil, centresInLine: false),
                               (r + b) * _px(1) > m0.ascent + 0.05 { grow = max(grow, (r + b) * _px(1) - m0.ascent) }
                        }
                        if grow > 0 {
                            RuleTrace.hit("word-raised-text-beside-an-inline-picture-grows-the-line-to-its-top")
                            Self._pairedLines[ObjectIdentifier(each)] = _PairedLines(painter: each, shifts: [grow], saving: -grow)
                        }
                    }
                    return each
                }
            }
            // One line of stretches of several heights is as tall as
            // its tallest and no more (a 14pt dash either side of a 9pt
            // page number): each face splits its height its own way,
            // and the engine would stack the deepest under the highest.
            // (On a line grid, every line of such a paragraph: each is as
            // many pitches as its tallest stretch takes, and Word's lines
            // of 12pt 標楷體 with Times digits and brackets among them are
            // two pitches each, where the engine stacked them 36 to 37.6
            // apart — zh-64044a1d.)
            let gridded = !_offGrid(i, document) && style.lineHeightPoints == nil && _grid(i, document).pitch != nil
            let lines = painter.computeLineMetrics().count
            // (And off the grid, every line of a paragraph whose lines
            // each hold some of its tallest stretch: zh-d68ac84a's cells
            // of 宋体 with Times digits in their first line set that
            // line 1.7pt high over two and three lines, and right over
            // one. A line without that stretch is its own height — the
            // footer of zh-1563bd74, an "X" in 16pt over a 14pt line.)
            // (A paragraph with an inline picture: the lines that hold its tallest text are held to that
            // text's height, and the lines that do not keep their own. lo-7ec36a70's Persian lines
            // stand 13.8pt apart in Word's print with a Latin-only line 12.0 under the last; a strut
            // for the whole paragraph set that line 13.9 down. The engine keeps each run's own total
            // and takes only the SPLIT above and below the baseline from an override, so every run
            // of the tallest stretch gets one height and one split — the share of Arial's line under
            // its baseline, by the face the run is drawn in, not the stand-in a font name resolves to.)
            if pil, theme.wordRules, RichTextTheme.wordWindowsPages, !Self._risesForNumber(inline) {
                var top = 0.0
                var counts: [Double: (Int, String?, Bool)] = [:]
                func tallest(_ s: InlineSpan) {
                    guard let t = s as? TextSpan else { return }
                    if let text = t.text, text.contains(where: { !Self._setsNoLine($0) }), let x = t.style, let size = x.fontSize, let h = x.height, size > 0.5, h > 0.05 {
                        top = max(top, size * h)
                        let key = (size * h * 100).rounded() / 100
                        counts[key] = ((counts[key]?.0 ?? 0) + text.count, x.fontFamily, x.fontWeight == .bold)
                    }
                    for c in t.children ?? [] { tallest(c) }
                }
                tallest(span)
                // (The stretch most of the text has among those within 3% of the tallest, as `_strut` does.)
                // (Only where our stand-in's own line is taller than the authored face's: Persian's 15.9 against Arial's 13.8.
                // (Persian's stand-in stands 15% over. Not on a line grid (docGrid type lines): zh-e49d7943 p14's Chinese title
                // line is a grid line, 36 by the grid and 38.6 in Word's print (baseline 104.2, picture 119.4), which the stand-in's
                // 38.4 matches; held to the runs' 36 it put the picture 2.4pt high. The 0.5% is rounding only.)
                if top > 0, let held = counts.filter({ $0.key >= top * 0.97 }).max(by: { $0.value.0 < $1.value.0 }) {
                    let standIn = painter.computeLineMetrics().map { $0.height }.filter { $0 >= held.key * 0.97 }.min() ?? 0
                    // (The authored face's own line where the layout knows it — 標楷體's 1.30 — else the runs' own height.)
                    var lab: String? = nil; var cjk = false; var sz = 0.0, hh = 1.0
                    func probe(_ s: InlineSpan) { guard let t = s as? TextSpan else { return }
                        if lab == nil, let x = t.style, let size = x.fontSize, let h = x.height, size * h >= top * 0.97, let tx = t.text, !tx.isEmpty {
                            lab = x.debugLabel; sz = size; hh = h; cjk = tx.unicodeScalars.contains { $0.value >= 0x2E80 && $0.value < 0xA000 } }
                        for c in t.children ?? [] { probe(c) } }
                    probe(span)
                    let authored = lab.flatMap { theme.faceResolver?($0, cjk) }?.naturalHeight.map { $0 * held.key / hh } ?? held.key
                    if (_offGrid(i, document) || _grid(i, document).pitch == nil), standIn > max(authored, held.key) * 1.005 {
                    let down = theme.descentShare(family: held.value.1, bold: held.value.2, italic: false)
                    func sized(_ s: InlineSpan) -> InlineSpan {
                        guard let t = s as? TextSpan else { return s }
                        var st = t.style
                        if let text = t.text, !text.isEmpty, let x = st, let size = x.fontSize, let h = x.height, size > 0.5, size * h >= top * 0.97 {
                            st = x.copyWith(ascentOverride: (1 - down) * held.key, descentOverride: down * held.key, height: held.key / size)
                        }
                        return TextSpan(text: t.text, children: t.children?.map { sized($0) }, style: st, recognizer: t.recognizer, locale: t.locale)
                    }
                    let each = TextPainter(text: sized(span), textAlign: align, textDirection: style.rightToLeft ? .rtl : .ltr)
                    each.fractionalLineHeights = painter.fractionalLineHeights
                    each.lineIndents = painter.lineIndents
                    if !inline.isEmpty { each.setPlaceholderDimensions(inline.map { $0.dimensions }) }
                    each.layout(minWidth: textWidth + slack, maxWidth: textWidth + slack)
                    if each.computeLineMetrics().count == lines { return each }
                    } else if !_offGrid(i, document), style.lineHeightPoints == nil || style.lineHeightIsMinimum, _grid(i, document).pitch != nil,
                              lines > 1, let ref = _strut(span, near: spacedOver || thaiNear, wide: thaiNear),
                              inline.filter({ $0.image?.float == nil }).count == 1,
                              inline.allSatisfy({ $0.image.map { $0.float.map { !$0.takesRoom } == true || ($0.float == nil && $0.textBox == nil && $0.name != "hr") } ?? false }),
                              case let metrics = painter.computeLineMetrics(), metrics.count == lines, metrics[0].height >= held.key * 0.97,
                              let box = painter.inlinePlaceholderBoxes?.last,
                              box.top >= metrics.dropLast().reduce(0, { $0 + $1.height }) - 0.5, metrics.last!.height > _px(_grid(i, document).pitch ?? 0) * 2 {
                        // (A title on the line grid with a picture after it on a
                        // line of its own: the title's line keeps its height but
                        // Word sets the baseline where the paragraph's strut puts
                        // it, the rest of the line under it. zh-e49d7943 p14: baseline
                        // 104.2 in Word's print, 109.6 with the stand-in's split.)
                        let flat = TextPainter(text: span, textAlign: align, textDirection: style.rightToLeft ? .rtl : .ltr, strutStyle: ref)
                        flat.fractionalLineHeights = painter.fractionalLineHeights
                        flat.lineIndents = painter.lineIndents
                        flat.setPlaceholderDimensions(inline.map {
                            PlaceholderDimensions(size: Size($0.dimensions.size.width, 0), alignment: .baseline, baseline: .alphabetic, baselineOffset: 0)
                        })
                        flat.layout(minWidth: lineWidth + slack, maxWidth: lineWidth + slack)
                        let strutLine = flat.computeLineMetrics().first
                        let above = strutLine?.baseline ?? 0
                        flat.dispose()
                        let total = metrics[0].height
                        if above > 1, above < metrics[0].baseline - 0.5, above < total {
                            RuleTrace.hit("word-grid-title-before-its-picture-keeps-the-strut-baseline")
                            func split(_ s: InlineSpan) -> InlineSpan {
                                guard let t = s as? TextSpan else { return s }
                                var st = t.style
                                if let text = t.text, !text.isEmpty, let x = st, let size = x.fontSize, let h = x.height, size > 0.5, size * h >= top * 0.97 {
                                    st = x.copyWith(ascentOverride: above, descentOverride: total - above, height: total / size)
                                }
                                return TextSpan(text: t.text, children: t.children?.map { split($0) }, style: st, recognizer: t.recognizer, locale: t.locale)
                            }
                            let each = TextPainter(text: split(span), textAlign: align, textDirection: style.rightToLeft ? .rtl : .ltr)
                            each.fractionalLineHeights = painter.fractionalLineHeights
                            each.lineIndents = painter.lineIndents
                            each.setPlaceholderDimensions(inline.map { $0.dimensions })
                            each.layout(minWidth: textWidth + slack, maxWidth: textWidth + slack)
                            if each.computeLineMetrics().count == lines { return each }
                        }
                    }
                }
            }
            if theme.wordRules, RichTextTheme.wordWindowsPages, !pil, !gridded, inline.isEmpty,
               let per = Self._heldWhereTaller(span, painter) {
                let lined = TextPainter(text: per, textAlign: align, textDirection: style.rightToLeft ? .rtl : .ltr)
                lined.fractionalLineHeights = painter.fractionalLineHeights
                lined.lineIndents = painter.lineIndents
                lined.layout(minWidth: textWidth + slack, maxWidth: textWidth + slack)
                if lined.computeLineMetrics().count == lines {
                    RuleTrace.hit("word-arabic-line-holds-taller-latin-below")
                    _heldTallerLatin.insert(i)
                    return lined
                }
                lined.dispose()
            }
            if painter.strutStyle == nil, theme.wordRules, !pil, !Self._risesForNumber(inline),
               // (On a grid, every line is held to the tallest, so not to
               // a word joiner's: the one before a compatibility ideograph
               // set in Noto Sans SC is Noto's line, and it held all of
               // its paragraph's lines to it — zh-c15af02e's "(一)…", one
               // "年" U+F98E on its first line, stood 46.2pt apart, where
               // Word's print keeps two pitches, 45.7, on every line, the
               // ones holding Noto's characters within 0.4 of it.)
               let strut = _strut(span, tallest: true, near: spacedOver || thaiNear, wide: thaiNear, joiners: !(gridded && lines > 1)),
               lines == 1 || gridded || Self._holdsYuJoiner(span) || Self._tallestOnEveryLine(span, strut, painter, lines: lines, near: spacedOver || thaiNear, wide: thaiNear) {
                if Self._holdsYuJoiner(span), !gridded, let per = Self._heldWhereJoined(span, painter, strut: strut, lineMultiple: style.lineSpacing) {
                    let lined = TextPainter(text: per, textAlign: align, textDirection: style.rightToLeft ? .rtl : .ltr)
                    lined.fractionalLineHeights = painter.fractionalLineHeights
                    lined.lineIndents = painter.lineIndents
                    if !inline.isEmpty { lined.setPlaceholderDimensions(inline.map { $0.dimensions }) }
                    lined.layout(minWidth: textWidth + slack, maxWidth: textWidth + slack)
                    if lined.computeLineMetrics().count == lines {
                        RuleTrace.hit("word-yu-joiner-holds-only-its-own-lines")
                        return lined
                    }
                    lined.dispose()
                }
                let held = TextPainter(text: span, textAlign: align, textDirection: style.rightToLeft ? .rtl : .ltr, strutStyle: strut)
                held.fractionalLineHeights = painter.fractionalLineHeights
                held.lineIndents = painter.lineIndents
                if !inline.isEmpty { held.setPlaceholderDimensions(inline.map { $0.dimensions }) }
                held.layout(minWidth: textWidth + slack, maxWidth: textWidth + slack)
                if held.computeLineMetrics().count == lines {
                    // (Unless a line holds none of the tallest stretch: it
                    // is as tall as its own stretches make it, each set in
                    // the middle of its pitches. Each of zh-1a3c7aa0's
                    // chemical names opens with a line of Arial alone,
                    // and Word's next baseline, among ideographs, is 25.0
                    // below it and those after 31.2 apart, in a table cell
                    // as in the body; ours were 31.2 each, and the annex
                    // ran three pages long. The engine splits a stretch's
                    // extra height by its ascent and descent, which sets
                    // YaHei's baseline 6pt low in two pitches: half above
                    // and half below is Word's.)
                    if lines > 1, gridded, let pitch = _grid(i, document).pitch, let size = strut.fontSize, let h = strut.height,
                       painter.computeLineMetrics().contains(where: { $0.height < size * h - _px(pitch) / 2 }) {
                        let even = TextPainter(text: Self._evenLeading(span), textAlign: align,
                                               textDirection: style.rightToLeft ? .rtl : .ltr)
                        even.fractionalLineHeights = painter.fractionalLineHeights
                        if !inline.isEmpty { even.setPlaceholderDimensions(inline.map { $0.dimensions }) }
                        even.layout(minWidth: textWidth + slack, maxWidth: textWidth + slack)
                        return even.computeLineMetrics().count == lines ? even : painter
                    }
                    return held
                }
            }
            // (An equation in the line is no picture here: its box stands in
            // the line as text does, and a stand-in's split beside it
            // stacks the line all the same — zh-c2c92639's "i   ——拆除…",
            // 宋体 spaces before the "——" set in Liberation Mono, stood
            // 1.1pt deeper than its ideographs, each such line 25.9pt
            // under the last where Word's print keeps 24.6.)
            if painter.strutStyle == nil, theme.wordRules, RichTextTheme.wordWindowsPages, document.usesEastAsianLayout,
               inline.allSatisfy({ $0.image.map { $0.name == "m:oMath" && $0.float == nil } ?? true }),
               let flat = Self._unstackedFaces(span, painter) {
                let flatter = TextPainter(text: flat, textAlign: align, textDirection: style.rightToLeft ? .rtl : .ltr)
                flatter.fractionalLineHeights = painter.fractionalLineHeights
                flatter.lineIndents = painter.lineIndents
                if !inline.isEmpty { flatter.setPlaceholderDimensions(inline.map { $0.dimensions }) }
                flatter.layout(minWidth: textWidth + slack, maxWidth: textWidth + slack)
                if flatter.computeLineMetrics().count == lines {
                    RuleTrace.hit("latin-standin-shares-ideograph-line")
                    return flatter
                }
            }
            return painter
        }
        for item in inline { if let image = item.image { _ensureDecoded(image) } }
        _inline[i] = inline.compactMap(\.image)
        _inlineBoxes[i] = inline.indices.filter { inline[$0].image != nil }
        _floats[i] = p.image?.float
        _floatImages[i] = p.image?.float != nil ? p.image : nil
        var painter = laidOut(span)
        _mixedFace[i] = nil
        if lines1(painter), let mixed = _mixedFaceSpan(span, p) {
            let again = laidOut(mixed.span)
            if lines1(again) { painter.dispose(); painter = again; _mixedFace[i] = (mixed.depth, mixed.size / _px(1)) } else { again.dispose() }
        } else if !lines1(painter), inline.isEmpty, let split = _mixedFaceLinesSpan(span, p, painter) {
            let again = laidOut(split)
            if again.computeLineMetrics().count == painter.computeLineMetrics().count {
                painter.dispose(); painter = again; _mixedFace[i] = (0, 0)
            } else { again.dispose() }
        }
        // East Asian line ends, as Word sets them: a closing mark that
        // would start a line hangs past the margin instead, and a line
        // half an em too long for its last character takes it anyway,
        // off one of its punctuation marks. The engine breaks lines by
        // width alone, so the marks are narrowed by what each line
        // needs and the paragraph laid out again.
        // (A line with a tab in it is fitted like any other, its tabs
        // as wide as they came out: a contents line typed with its own
        // dots takes its page number by what its commas give.)
        var fit = _fitEastAsianLines(p, at: i, document, textWidth: textWidth, first: painter, leadWidth: lead, tabs: tabs, leftTabs: leftTabs, runsPast: runsPast, beyond: beyond, tieShort: tieShort,
                                     lineIndents: besideLeftRoom != nil || _besideRightAt[i] != nil || (theme.wordRules && besideLineIndents.contains(where: { $0.right > 0 })) || _setup(ofParagraph: i).headerWrapLeft > 0 || !(colWrapBoxes?.isEmpty ?? true) ? besideLineIndents : [])
        if !fit.isEmpty {
            painter.dispose()
            painter = laidOut(_span(for: p, at: i, document, textWidth: textWidth, lead: lead, adjust: fit, held: tabsHeld).0)
        }
        // (A vertical section's ruby wider than its base: the line ends stand as the unwidened layout set them; the base is set
        // widened, and what that adds to a line past its room comes off the line's last character — see `_span`'s rubyKeep.)
        _rubyApply.remove(i)
        if theme.wordRules, let widen = _rubyWiden[i], !widen.isEmpty, !p.style.rightToLeft {
            let map = _map(i)
            let count = p.text.utf16.count
            let before = _lineStarts(painter, map, count: count)
            var adj = fit
            for k in 0 ..< before.count {
                let s0 = before[k], e = k + 1 < before.count ? before[k + 1] : count
                guard e > s0 else { continue }
                var added = 0.0
                for o in s0 ..< e { added += widen[o] ?? 0 }
                guard added > 0 else { continue }
                let boxes = painter.getBoxesForSelection(TextSelection(baseOffset: map.painter(s0), extentOffset: map.painter(e - 1) + 1))
                guard let right = boxes.map({ $0.right }).max(), let lastBox = boxes.last else { continue }
                let over = right + added - textWidth
                if over > 0 { adj[e - 1, default: 0] -= min(over, added, max(0, lastBox.right - lastBox.left - _px(0.5))) }
            }
            _rubyApply.insert(i)
            let widened = _span(for: p, at: i, document, textWidth: textWidth, lead: lead, adjust: adj, held: tabsHeld)
            let trial = laidOut(widened.0)
            let saved = _inserts[i]
            _inserts[i] = widened.2
            if _lineStarts(trial, _map(i), count: count) == before {
                painter.dispose()
                painter = trial
                fit = adj
            } else {
                trial.dispose()
                _inserts[i] = saved
                _rubyApply.remove(i)
            }
        }
        // (Korean under `w:wordWrap` off: a line whose words fill it to the margin and whose one space after them does not fit has
        // that space set at the START of the next line in Word's print, as a character; the engine hangs it at the end, so the
        // next line takes one character more. Each such space is held (`_wwSpaceStarts`) and the paragraph laid out again until none
        // is left. dx2 ed5bf93a.)
        _wwSpaceStarts[i] = nil
        // (Only where the East Asian fit above does not run, a file without `w:useFELayout`: where it does, it sets the line ends and this pass broke 14 of 83 wordWrap-off files.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, !document.usesEastAsianLayout, p.style.eastAsian["w:wordWrap"] == "0", style.alignment != .right, style.alignment != .center,
           p.text.utf16.contains(0x20), p.text.utf16.contains(where: { $0 >= 0xAC00 && $0 <= 0xD7A3 }) {
            let units = Array(p.text.utf16)
            var moved = Set<Int>()
            for _ in 0 ..< 12 {
                let map = _map(i)
                let starts = _lineStarts(painter, map, count: units.count)
                var found: Int? = nil
                if starts.count > 1 {
                    for k in 0 ..< starts.count - 1 {
                        let s0 = starts[k], e = starts[k + 1]
                        guard e - s0 >= 2, e <= units.count, units[e - 1] == 0x20, units[e - 2] != 0x20, units[e - 2] != 0x0A, !moved.contains(e - 1) else { continue }
                        let textBoxes = painter.getBoxesForSelection(TextSelection(baseOffset: map.painter(s0), extentOffset: map.painter(e - 1)))
                        let spaceBox = painter.getBoxesForSelection(TextSelection(baseOffset: map.painter(e - 1), extentOffset: map.painter(e - 1) + 1))
                        guard let first = textBoxes.first, let last = textBoxes.last, let sp = spaceBox.first else { continue }
                        let spaceWidth = sp.right - sp.left
                        var stretch = 0.0
                        for o in s0 ..< e - 1 where units[o] == 0x20 {
                            for b in painter.getBoxesForSelection(TextSelection(baseOffset: map.painter(o), extentOffset: map.painter(o) + 1)) { stretch += max(0, (b.right - b.left) - spaceWidth) }
                        }
                        let natural = last.right - first.left - stretch
                        if first.left + natural + spaceWidth > textWidth + 0.01, first.left + natural <= textWidth + 0.5 {
                            found = e - 1
                            break
                        }
                    }
                }
                guard let at = found else { break }
                moved.insert(at)
                _wwSpaceStarts[i] = moved
                painter.dispose()
                let refit = _span(for: p, at: i, document, textWidth: textWidth, lead: lead, adjust: fit, held: tabsHeld)
                painter = laidOut(refit.0)
                _inserts[i] = refit.2
            }
        }
        // The engine's justifying sets every space of a line to the one
        // step it puts between ideographs, and the two spaces after
        // "第一条" are gone. In a justified paragraph the spaces beside
        // East Asian text are therefore set again as no-break spaces —
        // characters like any other, which keep their width — but only
        // those inside a line, and only if every line then breaks
        // where it did: a no-break space at a line's end would count
        // against the line, and a plain one takes no room there.
        var held = tabsHeld
        @inline(never) func _q4() {
        if theme.wordRules, document.usesEastAsianLayout, style.alignment == .justify, p.text.utf16.contains(0x20) {
            let starts = _lineStarts(painter, _map(i), count: p.text.utf16.count)
            let hold = starts.count > 1 ? _spacesToHold(p, lineStarts: Set(starts)) : []
            if !hold.isEmpty {
                let (span, _, inserts) = _span(for: p, at: i, document, textWidth: textWidth, lead: lead, adjust: fit.isEmpty ? tabs : fit, held: hold.union(tabsHeld))
                let again = laidOut(span)
                if _lineStarts(again, _OffsetMap(lead: _lead(i), inserts: inserts), count: p.text.utf16.count) == starts || Self._holdsBreakOpening(p, hold, theme) {
                    painter.dispose()
                    painter = again
                    _inserts[i] = inserts
                    held = hold.union(tabsHeld)
                } else {
                    again.dispose()
                }
            }
        }
        }
        _q4()
        // (A justified line's automatic spaces — between an ideograph and a
        // Latin letter or digit — take its spare room first, each the same,
        // up to a quarter em more, and only what is left after them is
        // shared by the ideographs: zh-bee0b6d8's page 2 (Word for Windows,
        // mode 14, 12pt) has every ideograph step 12.00 and its automatic
        // spaces 3 to 6pt, from 0.3 on a line with room to spare to 3.0 more
        // on one with plenty, where ours spread it all over the ideographs.)
        // (A fitted group is not justified: a line that holds nothing but one stands as the left-aligned line, Word's print of lab
        // fit496b / xb jpn 496912's "金額" before "（年度ごとに記載）": 額 stays at the fitted pitch at every width, while a control
        // of the same two characters spaced by ideographic spaces is stretched. The stretch the engine gives such a line is taken back.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, style.alignment == .justify, style.eastAsian["w:jc"] != "distribute",
           textWidth < 50_000, !style.rightToLeft, besideLineIndents.allSatisfy({ $0.left == 0 && $0.right == 0 }),
           p.runs.contains(where: { Self._fitText($0.style.keptXML) != nil }), painter.computeLineMetrics().count > 1 {
            var grouped = Set<Int>()
            var at = 0
            for r in p.runs {
                if r.length > 0, Self._fitText(r.style.keptXML) != nil { for o in at ..< (at + r.length) { grouped.insert(o) } }
                at += r.length
            }
            let units = p.text.utf16.count
            let map = _OffsetMap(lead: _lead(i), inserts: _inserts[i])
            let starts = _lineStarts(painter, map, count: units)
            var only: [(Int, Int)] = []
            for (k, start) in starts.enumerated() where k + 1 < starts.count {
                let end = starts[k + 1]
                if end - start > 1, (start ..< end).allSatisfy({ grouped.contains($0) }) { only.append((start, end)) }
            }
            if !only.isEmpty {
                let (span, _, inserts) = _span(for: p, at: i, document, textWidth: textWidth, lead: lead, adjust: fit.isEmpty ? tabs : fit, held: held)
                let kept = align, keptLift = numberLift
                align = .left
                let flat = laidOut(span)
                align = kept
                numberLift = keptLift
                var indents = Array(repeating: LineIndent(), count: starts.count)
                var any = false
                for (start, end) in only {
                    let range = TextSelection(baseOffset: map.painter(start), extentOffset: map.painter(end))
                    guard let was = painter.getBoxesForSelection(range).map({ $0.right }).max(),
                          let flatRight = flat.getBoxesForSelection(range).map({ $0.right }).max(), was - flatRight > _px(0.05),
                          let line = starts.firstIndex(of: start) else { continue }
                    indents[line] = LineIndent(left: 0, right: was - flatRight)
                    any = true
                }
                flat.dispose()
                if any {
                    let keptIndents = painter.lineIndents
                    painter.lineIndents = indents
                    painter.layout(minWidth: textWidth + _px(tieSlack), maxWidth: textWidth + _px(tieSlack))
                    if _lineStarts(painter, map, count: units) == starts {
                        RuleTrace.hit("word-fitted-group-line-is-not-justified")
                    } else {
                        painter.lineIndents = keptIndents
                        painter.layout(minWidth: textWidth + _px(tieSlack), maxWidth: textWidth + _px(tieSlack))
                    }
                }
            }
        }
        if theme.wordRules, RichTextTheme.wordWindowsPages, document.usesEastAsianLayout, style.alignment == .justify,
           style.eastAsian["w:jc"] != "distribute", textWidth < 50_000, !style.rightToLeft,
           besideLineIndents.allSatisfy({ $0.left == 0 && $0.right == 0 }), painter.computeLineMetrics().count > 1 {
            var gaps: [Int: Double] = [:]
            let units = p.text.utf16.count
            let (span, _, inserts) = _span(for: p, at: i, document, textWidth: textWidth, lead: lead, adjust: fit.isEmpty ? tabs : fit, held: held,
                                           autoSpaces: { gaps[$0] = $1 })
            if !gaps.isEmpty {
                let map = _OffsetMap(lead: _lead(i), inserts: inserts)
                let starts = _lineStarts(painter, map, count: units)
                // The same text set to the left, to see how much room each line has.
                let kept = align, keptLift = numberLift
                align = .left
                let flat = laidOut(span)
                align = kept
                numberLift = keptLift
                var extra: [Int: Double] = [:]
                let cap = gaps.values.max() ?? 0
                for (k, start) in starts.enumerated() where k + 1 < starts.count {
                    let end = starts[k + 1]
                    let inside = gaps.keys.filter { $0 >= start && $0 + 1 < end }
                    guard !inside.isEmpty, end > start else { continue }
                    let boxes = flat.getBoxesForSelection(TextSelection(baseOffset: map.painter(start), extentOffset: map.painter(end)))
                    guard let right = boxes.map({ $0.right }).max() else { continue }
                    // (A space at the line's end is not part of it.)
                    let spare = textWidth - right
                    guard spare > _px(0.05) else { continue }
                    let each = min(spare / Double(inside.count), cap)
                    for g in inside { extra[g] = each }
                }
                flat.dispose()
                if !extra.isEmpty {
                    let widened = (fit.isEmpty ? tabs : fit).merging(extra) { $0 + $1 }
                    let (again, _, againInserts) = _span(for: p, at: i, document, textWidth: textWidth, lead: lead, adjust: widened, held: held)
                    let next = laidOut(again)
                    if _lineStarts(next, _OffsetMap(lead: _lead(i), inserts: againInserts), count: units) == starts {
                        painter.dispose()
                        painter = next
                        _inserts[i] = againInserts
                        fit = widened
                        RuleTrace.hit("word-justified-line-widens-automatic-spaces-first")
                    } else {
                        next.dispose()
                    }
                }
            }
        }
        // Distributed (`w:jc` distribute): the last line is spread too,
        // its first character at the line's start, its last ending at the
        // line's end and the room left shared evenly between them — in
        // Word's prints "適用考試名稱" 57.22pt apart across a 309pt cell,
        // "總計" one at each side of its cell, a cover's "山东省地方标准"
        // across the page. (The lines before it are justified.)
        if theme.wordRules, style.alignment == .justify, style.eastAsian["w:jc"] == "distribute",
           (p.cell?.textDirection ?? .horizontal) == .horizontal, textWidth < 50_000, !p.text.isEmpty {
            let units = Array(p.text.utf16)
            let map = _OffsetMap(lead: _lead(i), inserts: _inserts[i])
            let starts = _lineStarts(painter, map, count: units.count)
            var end = units.count
            while end > (starts.last ?? 0), [0x20, 0x09, 0x0A, 0x0B, 0x3000].contains(units[end - 1]) { end -= 1 }
            // (Each character's first unit: a surrogate pair is one.)
            let chars = ((starts.last ?? 0) ..< end).filter { !(units[$0] >= 0xDC00 && units[$0] <= 0xDFFF) }
            // (One character alone is centred: zh-bbbb2e6a's p13 cells,
            // "一", "二", "三" a cell, 16pt in 51.3pt of room, stand at the
            // middle in Word's print, 17.6pt in; ours set each at the start.)
            if let last = chars.last,
               let box = painter.getBoxesForSelection(TextSelection(baseOffset: map.painter(last), extentOffset: map.painter(end - 1) + 1)).last {
                // (A twentieth of a point short of the end — Word's unit —
                // or a point: set to the hair, the engine's rounding can
                // put the last character, a ")" in zh-454e2e29's
                // "(所屬機關名稱)", on a line of its own.)
                // (One character alone on a line that wraps on from the lines above is centred by
                // an indent of that line: a room before it would be dropped at the line's start.
                // lo zh-419ea527's "邮政编/码", the 码 at the middle, 418.5, in Word's print, where
                // ours stood at the start, 404.)
                var centred = false
                if chars.count == 1, last > 0, starts.count > 1, painter.lineIndents.allSatisfy({ $0.left == 0 && $0.right == 0 }) {
                    let room = textWidth - (box.right - box.left)
                    if room > _px(0.05) {
                        painter.lineIndents = Array(repeating: LineIndent(), count: starts.count - 1) + [LineIndent(left: room / 2, right: 0)]
                        painter.layout(minWidth: textWidth + (theme.wordRules ? _px(tieSlack) : 0), maxWidth: textWidth + (theme.wordRules ? _px(tieSlack) : 0))
                        centred = true
                        RuleTrace.hit("word-distributed-lone-last-character-is-centred")
                    }
                }
                for short in centred ? [] : [_px(0.05), _px(1)] {
                    let spare = textWidth - box.right - short
                    guard spare > 0 else { break }
                    var spread: [Int: Double] = [:]
                    if chars.count == 1 { spread[last] = spare / 2 }
                    for k in chars.dropFirst() { spread[k] = spare / Double(chars.count - 1) }
                    let (span, _, inserts) = _span(for: p, at: i, document, textWidth: textWidth, lead: lead, adjust: fit.isEmpty ? tabs : fit,
                                                   held: held, spread: spread)
                    let again = laidOut(span)
                    if _lineStarts(again, _OffsetMap(lead: _lead(i), inserts: inserts), count: units.count) == starts {
                        painter.dispose()
                        painter = again
                        _inserts[i] = inserts
                        break
                    }
                    again.dispose()
                }
            }
        }
        // (Thai distributed: every line but the last that ends at a space is spread over the clusters between its first and its
        // last letter, to the line's full width.)
        @inline(never) func _thaiDistribute() -> Bool {
            // (A paragraph with a box in it, a first-line indent's among them, is left as it is: its second layout loses the box.)
            let units = Array(p.text.utf16)
            let map = _OffsetMap(lead: _lead(i), inserts: _inserts[i])
            let starts = _lineStarts(painter, map, count: units.count)
            // (A first-line indent's box that no longer fits beside the first word stands alone on a line of its own: the line starts
            // read the same then, so the painter's line count is held as well.)
            let lineCount = painter.computeLineMetrics().count
            guard starts.count > 1 else { return false }
            // (Per line: its cluster heads and the room left after the last one.)
            var lines: [(heads: [Int], spare: Double, bare: Double, space: (offset: Int, width: Double)?)] = []
            for k in 0 ..< starts.count - 1 {
                let from = starts[k], to = starts[k + 1]
                guard to > from else { continue }
                // (A line that ends at a manual break is spread as well.)
                // (The break itself stands at the start of the next line, or ends this one.)
                func isBreak(_ u: UInt16) -> Bool { u == 0x0A || u == 0x0B || u == 0x2028 }
                let before = isBreak(units[to - 1]), after = to < units.count && isBreak(units[to])
                let broken = (before && to - 1 > from) || after
                guard units[to - 1] == 0x20 || (broken && !document.doesNotExpandShiftReturn) else { continue }
                let tail = before ? to - 2 : to - 1
                var last = tail
                while last > from, units[last] == 0x20 { last -= 1 }
                // (Clusters: a mark belongs to the letter before it, a leading vowel to the letter after it.)
                var heads: [Int] = []
                var afterLeading = false
                // (A line's blank lead, spaces or a tab that indent it, is not spread.)
                var first = from
                while first < last, units[first] == 0x20 || units[first] == 0x09 || units[first] == 0x3000 { first += 1 }
                for o in first ... last {
                    guard let u = Unicode.Scalar(UInt32(units[o])) else { continue }
                    let mark = u.properties.generalCategory == .nonspacingMark || u.properties.generalCategory == .spacingMark
                        || (units[o] >= 0xDC00 && units[o] <= 0xDFFF)
                    if mark && !heads.isEmpty { continue }
                    if afterLeading { afterLeading = false; continue }
                    // (Only Thai letters take room before them: Word's "3." label and its digits stay whole, 66cda9e3.)
                    guard (0x0E01 ... 0x0E5B).contains(units[o]) else { continue }
                    heads.append(o)
                    if (0x0E40 ... 0x0E44).contains(units[o]) { afterLeading = true }
                }
                guard heads.count > 1,
                      let box = painter.getBoxesForSelection(TextSelection(baseOffset: map.painter(heads[heads.count - 1]), extentOffset: map.painter(tail) + 1)).last else { continue }
                let spare = textWidth - box.right - _px(0.05)
                guard spare > 0 else { continue }
                let letters = painter.getBoxesForSelection(TextSelection(baseOffset: map.painter(heads[heads.count - 1]), extentOffset: map.painter(last) + 1)).last
                // (The space that ends the line hangs in Word; here it takes no width of its own, so the whole room can be spread.)
                var space: (offset: Int, width: Double)?
                if units[to - 1] == 0x20, last < to - 1, let gap = painter.getBoxesForSelection(TextSelection(baseOffset: map.painter(to - 1), extentOffset: map.painter(to - 1) + 1)).last,
                   gap.right - gap.left > 0 { space = (to - 1, gap.right - gap.left) }
                lines.append((heads, spare, letters.map { textWidth - $0.right - _px(0.05) } ?? spare, space))
            }
            guard !lines.isEmpty else { return false }
            // (A line's room is what is left after its last letter; `bare` leaves out the space that follows.)
            func attempt(_ t: Double) -> (TextPainter, [Int: Double], [Int], [Int])? {
                var spread: [Int: Double] = [:]
                for line in lines {
                    // (t is 1 for the whole room, 0 for the room left after the space.)
                    let room = line.spare + t * (line.bare - line.spare)
                    for h in line.heads.dropFirst() { spread[h] = room / Double(line.heads.count - 1) }
                    if let space = line.space, t >= 1 { spread[space.offset] = -space.width }
                }
                let (span, _, inserts) = _span(for: p, at: i, document, textWidth: textWidth, lead: lead,
                                               adjust: fit.isEmpty ? (hangs.isEmpty ? tabs : tabs.merging(hangs) { $0 + $1 }) : fit,
                                               held: held, spread: spread)
                let again = laidOut(span)
                let st = _lineStarts(again, _OffsetMap(lead: _lead(i), inserts: inserts), count: units.count)
                guard st == starts, again.computeLineMetrics().count == lineCount else { again.dispose(); return nil }
                return (again, spread, inserts, st)
            }
            // (Word fills the line to the margin and hangs the space: where the full room breaks a line early, the largest share
            // of it that keeps every line break is found by halving between the whole room and the room left after the space.)
            var best = attempt(1)
            if best == nil {
                var lo = 0.0, hi = 1.0
                guard var kept = attempt(0) else { return false }
                for _ in 0 ..< 6 {
                    let mid = (lo + hi) / 2
                    if let t = attempt(mid) { kept.0.dispose(); kept = t; lo = mid } else { hi = mid }
                }
                best = kept
            }
            guard let (again, _, inserts, _) = best else { return false }
            painter.dispose()
            painter = again
            _inserts[i] = inserts
            RuleTrace.hit("word-thai-distribute-spreads-lines-over-their-clusters")
            return true
        }
        // (Where no spread is made the lines stay as the engine's justify sets them: the left-aligned layout read their room.)
        @inline(never) func _thaiJustified() {
            align = Self._textAlign(style.alignment)
            let (span, _, inserts) = _span(for: p, at: i, document, textWidth: textWidth, lead: lead,
                                           adjust: fit.isEmpty ? (hangs.isEmpty ? tabs : tabs.merging(hangs) { $0 + $1 }) : fit, held: held)
            let again = laidOut(span)
            align = .left
            painter.dispose()
            painter = again
            _inserts[i] = inserts
        }
        if thaiDistributed, (p.cell?.textDirection ?? .horizontal) == .horizontal, textWidth < 50_000, !_thaiDistribute() { _thaiJustified() }
        // Whole pixels: a page break clips between two lines, and a
        // fractional line box leaves the previous line's descenders peeking
        // into the next page (and its ascenders shaved off the previous).
        // A border's line and its gap lie between the spacing and the text.
        // (Paragraphs of one border set run together under one box: the
        // top line over the first, the bottom one under the last, and no
        // room for either between — bug65649's specification lines, each
        // ruled under in grey, stand 12.5pt apart in Word's print, not
        // the 13 ours gave them for a line under each.)
        // (A compound line takes all its lines' room, as a cell's does:
        // zh-69bbcc3c's letterhead rule, thinThickSmallGap at 2.25pt, is
        // 2.16 + 0.72 + 0.72 in Word's print and the page under it 1.14pt
        // lower than ours was.)
        let bareBreak = _emptyBreakFragment(i, document)
        let bTop = bareBreak || _bordersJoin(i - 1, i, document) ? 0 : style.borders?.top.map { _px($0.space + Self._ruleRoom($0.style, $0.width)) } ?? 0
        let bBottom = bareBreak || _bordersJoin(i, i + 1, document) ? 0 : style.borders?.bottom.map { _px($0.space + Self._ruleRoom($0.style, $0.width)) } ?? 0
        let spacing = _spacing(i, document)
        // (Exact under Word's rules, whose lines keep their fractions
        // too: 14pt is 18.67px on a screen, and a whole pixel more under
        // every web-spaced paragraph stood Word's 14pt gap at 14.75.)
        // (A text frame with no text beside it, over its vSpace, leaves the
        // text after it 2 x that and 2.7pt more below it: tdf105035_framePrB's
        // title and authors frames, vSpace 187 twips, put the authors line
        // 21.0pt and the abstract 21.8pt lower than ours, with a "notBeside"
        // frame's own spacing after counted. One witness's constant.)
        var frameGap = 0.0
        if theme.wordRules, p.cell == nil, i > 0, case let above = document.paragraphs[i - 1], above.cell == nil,
           let aboveXML = above.style.frameXML, aboveXML != style.frameXML,
           above.style.frame?.verticalAnchor == "text", aboveXML.containsSubstring("w:wrap=\"notBeside\""), !aboveXML.containsSubstring("w:h=\""),
           let at = aboveXML.firstRange(of: "w:vSpace=\""),
           let v = Double(aboveXML[at.upperBound...].prefix { $0 != "\"" }), v > 0 {
            frameGap = 2 * v / 20 + 2.7
        }
        // (A cell's first paragraph its own page break opens drops its space
        // before from 2013's layout on, as T238's body paragraph does:
        // zh-ab9cbe66's "立即學習效果" (84 twips before, mode 15, p63 and p56)
        // stands 4.2pt over where ours did, and the page's rows with it.)
        let cellBreakLead = theme.wordRules && RichTextTheme.wordWindowsPages && (document.compatibilityMode ?? 12) >= 15
            && style.cellBreakOpens && p.cell != nil && (i == 0 || document.paragraphs[i - 1].cell != p.cell)
        // (A document with `suppressTopSpacing` stands the first line of a page of exact
        // lines higher by 0.8 x (the height - 12pt), and the lines under it with it. Lab
        // stsp, Word for Windows: 9.6, 4.8, 14.4 and 19.2pt at 24, 18, 30 and 36pt
        // whatever the font size; nothing at 12pt or at an automatic height; a space
        // before stays. Here for the document's first paragraph and one that opens a page
        // by a break; lo orrick's body, 9.5pt high in Word's print.)
        var topRaise = 0.0
        if theme.wordRules, RichTextTheme.wordWindowsPages, document.suppressesTopSpacing, p.cell == nil,
           i == 0 || _pageBreak[i], let h = style.lineHeightPoints, h > 12 {
            // (An "at least" height stands h - 9.4pt higher instead: lab atleast, Calibri 11 and 16
            // at 13, 16, 20, 24 and 30pt: first baseline 78.6 on page 1 and every later page.)
            if style.lineHeightIsMinimum {
                RuleTrace.hit("suppress-top-spacing-raises-the-page-first-atleast-line")
                topRaise = _px(h - 9.4)
            } else {
                RuleTrace.hit("suppress-top-spacing-raises-the-page-first-exact-line")
                topRaise = _px(0.8 * (h - 12))
            }
        }
        let before = (theme.wordRules ? (cellBreakLead ? 0 : spacing.before) + bTop : (spacing.before + bTop).rounded()) + _px(frameGap) - topRaise + _sectionEndnotesHeight(before: i, document)
        let after = spacing.after + bBottom
        // Where the engine put the baseline (a strut's even leading) is
        // not where Word has it: the text is drawn from as much lower.
        _inkShift[i] = 0
        _numberLiftShift[i] = 0
        var segoeLift = 0.0   // what a Segoe UI Symbol shape adds over the first line (`RichTextTheme.segoeSymbolShapes`)
        // (A paragraph whose runs differ only by a raised or lowered one
        // has no strut, and its lines are each as tall as one of its own
        // text: its baseline wants the same correction — endnotes' "A
        // pendant worn…", its "i" mark among 11pt Calibri, stood 1.6pt
        // under Word's.)
        // (A paragraph with no strut whose first line holds a character the
        // face's chain sends to Yu Gothic or JhengHei has those faces' own
        // line height, and its text wants the same first-line correction:
        // lab cm236d's JP paragraph with 书/东 stood 1.85pt low.)
        let chainFaceLine: Bool = {
            guard theme.wordRules, painter.strutStyle == nil, p.image == nil, !p.text.isEmpty else { return false }
            let firstEnd = painter.getLineBoundary(TextPosition(offset: 0)).end - _lead(i)
            let units = Array(p.text.utf16)
            var start = 0
            for run in p.runs where run.length > 0 {
                defer { start += run.length }
                guard start < firstEnd else { break }
                guard let face = theme.faceResolver?(run.style.eastAsiaFontFamily ?? _named(p, document)?.char.eastAsiaFontFamily
                                                     ?? _normalChar(document)?.eastAsiaFontFamily ?? run.style.fontFamily
                                                     ?? _named(p, document)?.char.fontFamily ?? theme.fontFamily, true),
                      let covers = face.covers, face.chainFaceLines, let chain = face.uncoveredChain else { continue }
                let end = min(start + run.length, firstEnd, units.count)
                guard start < end else { continue }
                for ch in String(decoding: units[start ..< end], as: UTF16.self) {
                    guard let u = ch.unicodeScalars.first?.value, Self._isEastAsianScalar(u), !covers.contains(u) else { continue }
                    let k = chain.firstIndex { $0.covers?.contains(u) ?? true } ?? chain.count - 1
                    if Self._chainFaceLines[chain[k].family] != nil { return true }
                }
            }
            return false
        }()
        let scriptsOnly = painter.strutStyle == nil && p.inlineImages.isEmpty && p.runs.contains { $0.style.script != .normal }
            && Set(painter.computeLineMetrics().map { ($0.height * 100).rounded() }).count == 1
        // (… nor does one whose runs differ in size, which has no strut
        // either: zh-31d580df's "(2)人員配置：…" — 10.5pt text and a 12pt
        // "（★參考撰寫說明2、3）" at the end, 1.25 lines — stood its first
        // line 5pt under Word's print.)
        // (Only where its first line is of one size and a later run differs:
        // a title whose first line mixes sizes — zh-454e2e29's 18pt, 14pt
        // and 24pt "（機關名稱機關代號）" — keeps its own.)
        var mixedSizes = false
        var latinFirstLine = false
        if painter.strutStyle == nil, p.inlineImages.isEmpty, !p.text.isEmpty {
            let firstEnd = painter.getLineBoundary(TextPosition(offset: 0)).end - _lead(i)
            var start = 0
            var onFirst = Set<Double>(), later = Set<Double>()
            for run in p.runs where run.length > 0 {
                defer { start += run.length }
                let from = p.text.utf16.index(p.text.utf16.startIndex, offsetBy: min(start, p.text.utf16.count))
                let to = p.text.utf16.index(from, offsetBy: min(run.length, p.text.utf16.count - min(start, p.text.utf16.count)))
                // (A paragraph opening on a line break: that break's run sizes the empty first line.)
                if p.text[from ..< to].allSatisfy(\.isWhitespace), !(theme.wordRules && start == 0 && p.text.hasPrefix("\n") && run.length == 1) { continue }
                let size = run.style.fontSize ?? -1
                if start < firstEnd || (theme.wordRules && start == 0 && run.length == 1 && p.text.hasPrefix("\n")) { onFirst.insert(size) } else { later.insert(size) }
            }
            mixedSizes = onFirst.count == 1 && later.contains { !onFirst.contains($0) }
            // (… and a first line whose sizes differ by no more than a
            // point — 15.5 and 15 — is corrected like one of a single size:
            // zh-202582e2's item 3, runs of sz 31 then 30, stood 6pt low
            // where Word's print has it at the 31's baseline whatever the
            // later lines' runs are.)
            if !mixedSizes, onFirst.count > 1, !onFirst.contains(-1), let lo = onFirst.min(), let hi = onFirst.max(), hi - lo <= 5.0 { mixedSizes = true }
            // (… an inherited size counts as the paragraph's own: a 10pt label and an underscore fill that takes the 11pt of the
            // style, in one line, are corrected as sizes a point apart. sa1 8cfaa504, lab8cfa.)
            if !mixedSizes, theme.wordRules, RichTextTheme.wordWindowsPages, onFirst.count > 1, onFirst.contains(-1),
               // (Latin text only: a complex-script or East Asian run takes its own size, szCs, so the plain size says nothing there:
               // dx2 f0001d05's Hindi check-box lines, which stood 2.8pt higher than Word's.)
               p.text.unicodeScalars.allSatisfy({ $0.value < 0x0590 || ($0.value >= 0x2000 && $0.value <= 0x206F) }),
               case let inherited = _named(p, document)?.char.fontSize ?? theme.fontSize,
               case let resolved = Set(onFirst.map { $0 == -1 ? inherited : $0 }), resolved.count > 1,
               let lo = resolved.min(), let hi = resolved.max(), hi - lo <= 5.0 {
                RuleTrace.hit("word-inherited-size-counts-as-the-style-size-in-a-mixed-size-first-line")
                mixedSizes = true
            }
            // (… and one of a single size whose faces differ, so that its lines
            // differ in height: zh-51af781b's 方正楷体_GBK (a YaHei stand-in) among
            // 仿宋 text. Word puts the extra of 1.5 lines under each line's tallest
            // face, as it does under the tallest size.)
            if !mixedSizes, onFirst.count == 1, later.isSubset(of: onFirst), theme.wordRules, RichTextTheme.wordWindowsPages {
                let metrics = painter.computeLineMetrics()
                if metrics.count > 1, metrics.contains(where: { abs($0.ascent - metrics[0].ascent) > _px(0.05) }),
                   Set(p.runs.filter { $0.length > 0 }.map { $0.style.fontFamily ?? "" }).count > 1
                    // (… or runs of one face of which some hold East Asian text and some none, whose
                    // lines the engine sets by different heights: f8ff8a48's Han title over a Latin
                    // address after a line break stood 3.7pt low.)
                    || _holdsEastAsianAndLatinRuns(p, document: document) {
                    RuleTrace.hit("zh-51af781b-faces-of-one-size-put-the-extra-under-the-tallest-face")
                    mixedSizes = true
                }
            }
            // A first line with no East Asian character over a later line that has one, in one run (a line break inside it):
            // Word stands the first line on its Latin face, as a paragraph of Latin lines does (lab cm2a, cases 14-18: "3." over a
            // Chinese line stands 24.96 under the line above, where the Mincho height gave 26.65), but the engine sets it by the
            // taller line's face (no strut, as `_strut` finds the lines of unequal heights).
            if !mixedSizes, theme.wordRules, RichTextTheme.wordWindowsPages, painter.computeLineMetrics().count > 1 {
                var off = 0, firstHas = false, laterHas = false, firstAny = false
                for run in p.runs where run.length > 0 {
                    let hinted = (run.style.fontHint ?? _named(p, document)?.char.fontHint) == "eastAsia"
                    let a = p.text.utf16.index(p.text.utf16.startIndex, offsetBy: min(off, p.text.utf16.count))
                    let b = p.text.utf16.index(a, offsetBy: min(run.length, p.text.utf16.count - min(off, p.text.utf16.count)))
                    for ch in p.text[a ..< b] {
                        defer { off += ch.utf16.count }
                        if Self._setsNoLine(ch) { continue }
                        let ea = Self.isEastAsian(ch, hinted: hinted)
                        if off < firstEnd { if ea { firstHas = true } else { firstAny = true } } else if ea { laterHas = true }
                    }
                }
                if firstAny, !firstHas, laterHas {
                    RuleTrace.hit("word-latin-first-line-keeps-its-face-over-a-later-east-asian-line")
                    latinFirstLine = true
                    mixedSizes = true
                }
            }
        }
        // (The "position" of a Wingdings 2 bullet's numbering run, where the box is lowered or stands: see `_span`.)
        var w2Done = false
        var w2Trim = 0.0   // what the engine's first line stands over the bullet line's ascent (its ink is lifted by it above)
        func _w2Half() -> Double? {
            guard theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil, p.style.list != nil,
                  _levelNumberFonts(p, document).latin?.lowercased() == "wingdings 2",
                  let xml = p.style.listId.flatMap({ document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.numberRPrXML }) else { return nil }
            var half = 0.0
            if let pr = xml.rangeOfSubstring("<w:position w:val=\"") {
                half = Double(xml[pr.upperBound...].prefix { $0 != "\"" }) ?? 0
            }
            return half <= 0 ? half : nil
        }
        func _symbolBulletOnNaturalLine(_ p: RichParagraph, painter: TextPainter, style: RichParagraphStyle, document: RichDocument) -> Bool {
            theme.wordRules && RichTextTheme.wordWindowsPages && p.style.list == .bullet && painter.strutStyle == nil
                && style.lineHeightPoints == nil && style.lineSpacing > 1.01
                && _levelNumberFonts(p, document).latin?.lowercased() == "symbol"
        }
        @inline(never) func _blk5() {
        if theme.wordRules, p.image == nil, !p.text.isEmpty, painter.strutStyle != nil || _heldTallerLatin.contains(i) || _symbolBulletOnNaturalLine(p, painter: painter, style: style, document: document) || chainFaceLine || scriptsOnly || mixedSizes || Self._startsWithEmoji(p.text) || _koreanSymbolFirstLineRaise(p, painter: painter, lead: _lead(i), named: _named(p, document), document: document) != nil,
           let line = painter.computeLineMetrics().first {
            let named = _named(p, document)
            let pitch = _offGrid(i, document) ? nil : _grid(i, document).pitch
            var at = 0
            var lead: (CharStyle, Bool) = (p.runs[0].style, false)
            // (A line opening on an anchored picture's mark is sized by the text after it:
            // lo-7ec36a70's Persian line, Times 10 for the mark's run, stood 2pt high.)
            // (Several anchors in a row open the line the same: the text's run is the one that sets it, not a second anchor's,
            // dx2 48e5a592's "PUNTOS POR PASAJERO" line, two ovals ahead of it, stood 3.55pt low.)
            if theme.wordRules, p.runs[0].length > 0, p.text.unicodeScalars.prefix(p.runs[0].length).allSatisfy({ $0 == "\u{FFFC}" }) {
                var off = p.runs[0].length
                var found: Run? = nil
                let u = Array(p.text.utf16)
                for r in p.runs.dropFirst() where r.length > 0 {
                    let end = min(u.count, off + r.length)
                    let anchorsOnly = RichTextTheme.wordWindowsPages && off < end && u[off ..< end].allSatisfy { $0 == 0xFFFC }
                    off = end
                    if !anchorsOnly { found = r; break }
                }
                if let next = found { lead = (next.style, false) }
            }
            search: for run in p.runs {
                let hinted = (run.style.fontHint ?? named?.char.fontHint) == "eastAsia"
                let a = p.text.utf16.index(p.text.utf16.startIndex, offsetBy: at)
                let b = p.text.utf16.index(a, offsetBy: run.length)
                at += run.length
                // (Not white space: a U+3000 sets no line — see `_strut`.)
                for ch in p.text[a ..< b] where !Self._setsNoLine(ch) && Self.isEastAsian(ch, hinted: hinted) {
                    if latinFirstLine { break search }
                    if !lead.1 { lead = (run.style, true) }
                    // (An em dash further on may stand the line taller: keep looking for it.)
                    if theme.wordRules, RichTextTheme.wordWindowsPages, p.text.contains(Self._emDash) { continue }
                    break search
                }
                // (An unhinted em dash over an East Asian hAnsi face stands the line on that face: see `_eastDashLeadStyle`.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, !hinted, run.style.inlineImage == nil, p.text[a ..< b].contains(Self._emDash),
                   let dashStyle = _eastDashLeadStyle(run.style, named: named) {
                    lead = (dashStyle, true)
                    break search
                }
            }
            if var target = theme.baseline(for: lead.0, in: style, named: named, eastAsian: lead.1, gridPitch: pitch, centresInLine: document.spacesForUnderline) {
                // (The line's baseline is its tallest run's, where the
                // text is Latin: form_footnotes' "D - " box in Symbol
                // after 11pt spaces sets "Concessão" a point lower than
                // the 10pt lines beside it in Word's print.)
                // Under "at least", choose the text's controlling baseline
                // before adding minimum-height leading. A small leading run
                // otherwise wins when the minimum exceeds both runs' heights.
                if !lead.1, style.lineHeightPoints == nil || style.lineHeightIsMinimum {
                    let firstEnd = painter.getLineBoundary(TextPosition(offset: 0)).end - _lead(i)
                    var naturalStyle = style
                    naturalStyle.lineHeightPoints = nil
                    var naturalBaseline = -Double.infinity
                    var minimumTarget: Double?
                    var start = 0
                    for run in p.runs where run.length > 0 {
                        defer { start += run.length }
                        guard start < firstEnd else { break }
                        if run.style.inlineImage != nil || run.style.script != .normal { continue }
                        // (Nor a run of white space alone: see `_strut`.)
                        let from = p.text.utf16.index(p.text.utf16.startIndex, offsetBy: min(start, p.text.utf16.count))
                        let to = p.text.utf16.index(from, offsetBy: min(run.length, p.text.utf16.count - min(start, p.text.utf16.count)))
                        if p.text[from ..< to].allSatisfy(Self._setsNoLineBesideText) { continue }
                        if let b = theme.baseline(for: run.style, in: style, named: named, eastAsian: false, gridPitch: pitch, centresInLine: document.spacesForUnderline) {
                            if style.lineHeightPoints != nil,
                               let own = theme.baseline(for: run.style, in: naturalStyle, named: named, eastAsian: false, gridPitch: pitch, centresInLine: document.spacesForUnderline) {
                                if own > naturalBaseline {
                                    naturalBaseline = own
                                    minimumTarget = b
                                }
                            } else if !_heldTallerLatin.contains(i) {
                                // (Not where a taller Latin run takes its extra below the line, see `_heldWhereTaller`: Word keeps the first baseline on the lead face's.)
                                target = max(target, b)
                            }
                        }
                    }
                    if let minimumTarget { target = minimumTarget }
                }
                // (… and where its first line holds a character an
                // embedded subset lacks, the face Word sets that in: its
                // YaHei, whose baseline under the line's top is lower than
                // the subset's square one — zh-92373179's 1.5-spaced 16pt
                // lines stood 4.1pt high of Word's print.)
                if lead.1 {
                    let firstEnd = painter.getLineBoundary(TextPosition(offset: 0)).end - _lead(i)
                    let units = Array(p.text.utf16)
                    var start = 0
                    var seenAcross = Set<String>()
                    scan: for run in p.runs where run.length > 0 {
                        defer { start += run.length }
                        guard start < firstEnd else { break }
                        guard let face = theme.faceResolver?(run.style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily
                                                             ?? _normalChar(document)?.eastAsiaFontFamily ?? run.style.fontFamily
                                                             ?? named?.char.fontFamily ?? theme.fontFamily, true),
                              let covers = face.covers, let alt = face.uncoveredFamily else { continue }
                        let end = min(start + run.length, firstEnd, units.count)
                        guard start < end else { continue }
                        // (Of each face a chain of them sets on the line, the
                        // tallest: zh-5450d509's "各省…" opens in MS Gothic and
                        // goes on in JhengHei, and Word's print stands the
                        // line on JhengHei's baseline, 4.4pt under MS
                        // Gothic's. One face alone, the first such character's.)
                        var at: Int? = nil
                        for ch in String(decoding: units[start ..< end], as: UTF16.self) {
                            // (Not the object mark of a drawing: it is no character of the face, and Word sets no line by it — zh-8e8d4c40's title, 12pt 標楷體 after a wrapSquare box, stood 2pt low on JhengHei's baseline.)
                            guard let u = ch.unicodeScalars.first?.value, u >= 0x2E80, u != 0xFFFC else { continue }
                            if covers.contains(u) { at = nil; continue }
                            var r = run.style
                            if let chain = face.uncoveredChain {
                                if let k = at, chain[k].covers?.contains(u) ?? true {} else { at = chain.firstIndex { $0.covers?.contains(u) ?? true } ?? chain.count - 1 }
                                guard seenAcross.insert(chain[at!].family).inserted else { continue }
                                r.eastAsiaFontFamily = chain[at!].family
                            } else { r.eastAsiaFontFamily = alt }
                            if let b = theme.baseline(for: r, in: style, named: named, eastAsian: true, gridPitch: pitch, centresInLine: document.spacesForUnderline) { target = max(target, b) }
                            if face.uncoveredChain == nil { break scan }
                        }
                    }
                    // (… and the tallest East Asian run on it, not the
                    // first: zh-17ac8aa2's "□" in 黑体 before "若本机关…" in
                    // 楷体_GB2312 stood the line's text at the □'s one-pitch
                    // baseline, 7pt high of Word's print, in the two-pitch
                    // line the 楷体 makes.)
                    start = 0
                    var tallest = 0.0
                    var latin: [CharStyle] = []
                    for run in p.runs where run.length > 0 {
                        defer { start += run.length }
                        guard start < firstEnd else { break }
                        if run.style.inlineImage != nil || run.style.script != .normal { continue }
                        let hinted = (run.style.fontHint ?? named?.char.fontHint) == "eastAsia"
                        let end = min(start + run.length, firstEnd, units.count)
                        guard start < end else { continue }
                        let text = String(decoding: units[start ..< end], as: UTF16.self)
                        if text.contains(where: { !Self._setsNoLine($0) && Self.isEastAsian($0, hinted: hinted) }) {
                            if let b = theme.baseline(for: run.style, in: style, named: named, eastAsian: true, gridPitch: pitch, centresInLine: document.spacesForUnderline) { target = max(target, b) }
                            tallest = max(tallest, theme.naturalLine(for: run.style, named: named, eastAsian: true) ?? .infinity)
                        }
                        // (A tab sets no line beside text — lab `ttab`: a 48pt tab run at the end of
                        // lo-11ad5a95's "U+0009" rows stood the 12pt label 11pt low, out of its line.)
                        if text.contains(where: { !Self._setsNoLineBesideText($0) && !Self.isEastAsian($0, hinted: hinted) }) { latin.append(run.style) }
                    }
                    // (… and a Latin run's, where its line is the taller:
                    // zh-77bd4900's "①+②-③=④", PMingLiU circled digits
                    // between 標楷體 signs — YaHei to Word on a Mac — stands
                    // at YaHei's baseline in Word's print. A shorter one
                    // sets nothing: zh-c25d08c5's Times "2022" in YaHei
                    // lines on a grid, centred in its pitch, stood 3.8pt
                    // under them.)
                    for r in latin {
                        guard let own = theme.naturalLine(for: r, named: named, eastAsian: false), own > tallest + 0.01,
                              let b = theme.baseline(for: r, in: style, named: named, eastAsian: false, gridPitch: pitch, centresInLine: document.spacesForUnderline) else { continue }
                        target = max(target, b)
                    }
                }
                if style.lineHeightPoints == nil || style.lineHeightIsMinimum {
                    let firstEnd = painter.getLineBoundary(TextPosition(offset: 0)).end - _lead(i)
                    let units = Array(p.text.utf16)
                    var start = 0
                    // (… and Segoe UI Symbol's, where the line holds a shape
                    // Word sets in it — see `RichTextTheme.segoeSymbolShapes`: its
                    // ascent, 2210 of 2048, over the baseline; a colour emoji is Segoe UI Emoji's, whose
                    // ascent is the same: lab emo1, a line starting 🔬 stands 1.5-1.7pt lower.)
                    do {
                        for run in p.runs where run.length > 0 {
                            defer { start += run.length }
                            guard start < firstEnd else { break }
                            let end = min(start + run.length, firstEnd, units.count)
                            guard start < end, run.style.fontHint != "eastAsia",
                                  theme.faceResolver?(run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false)?.isEastAsian != true
                                    // (❏ is in no Korean face: a run naming only 한양신명조 for its
                                    // ascii still draws it in Segoe UI Symbol, xd 07eecf7a p2.)
                                    || units[start ..< end].contains(0x274F),
                                  Self._holdsSegoeGlyph(units, start, end, emojiOnly: !lead.1)
                                    || (RichTextTheme.wordWindowsPages && units[start ..< end].contains(where: { u in
                                        // (Only where the run's Latin face has no such glyph, by its cmap (Georgia's holds no ▸); a face that holds it draws it itself.)
                                        RichTextTheme.cambriaMathShapes.contains(UInt32(u))
                                            && Self._latinFaceLacks(run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily ?? "", UInt32(u)) != false })) else { continue }
                            // (Word for Windows sets "▸" in Cambria Math, whose line is 1.172 em:
                            // 2400 units, its descent Cambria's 449, so 1951 above the baseline.
                            // xb jpn 3f592b p23: Georgia 12pt lines 24.7pt apart, ours 24.2.)
                            let cambriaMath = !Self._holdsSegoeGlyph(units, start, end, emojiOnly: !lead.1)
                            let size = run.style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                            // (The line as much taller: what stands under it
                            // goes as much lower — p7's third note line to
                            // p8, as in Word's print.)
                            let shapeAscent = size * (cambriaMath ? 1951.0 : 2210.0) / 2048
                            segoeLift = max(segoeLift, shapeAscent - target)
                            target = max(target, shapeAscent)
                        }
                    }
                }
                if lead.1 {
                    // (… and its list label's, in Word for Windows, where the
                    // label stands lower under the line's top than the text:
                    // the line as much taller, as for a Segoe UI Symbol shape.
                    // zh-6d402586's numbered items, 14pt 標楷體 at 1.629 lines
                    // under "%1." in 微軟正黑體 12pt, open each 2.1pt lower in
                    // Word's print than ours; zh-8e8d4c40's "2、" (MS Mincho)
                    // over 12pt DFKai-SB, 0.6.)
                    if RichTextTheme.wordWindowsPages, style.lineHeightPoints == nil || style.lineHeightIsMinimum,
                       p.style.list != nil, let label = listLabel(i, document), !label.isEmpty,
                       // (Not a bullet of a symbol face, whose private-use character is no
                       // East Asian one: lo-ca9b51bc's 12pt Wingdings bullet over 9pt text
                       // lifted its lines 9pt, where Word's stand the text's own.)
                       !["symbol", "wingdings", "wingdings 2", "wingdings 3", "webdings"].contains(_levelNumberFonts(p, document).latin?.lowercased() ?? "") {
                        let markerChar = _markerChar(p, document)
                        let ea = label.contains(where: { Self.isEastAsian($0, hinted: true) })
                        // (Only a label set in an East Asian face: zh-de073ee5's
                        // "2." in SimSun 14pt stands lower than its 標楷體 text
                        // and lifts the line, though its own line is no taller;
                        // zh-74ef1528's "6." in Normal's Latin face and
                        // zh-c399c91a's in LinTimes set nothing in Word's print.)
                        if ea || theme.faceResolver?(markerChar.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false)?.isEastAsian == true,
                           let b = theme.baseline(for: markerChar, in: style, named: named, eastAsian: ea, gridPitch: pitch, centresInLine: document.spacesForUnderline),
                           b > target + 0.01 {
                            segoeLift = max(segoeLift, b - target)
                            target = b
                        }
                    }
                }
                // (A first line of Devanagari-to-Telugu letters stands on the ascent of the face Word
                // draws them in: Nirmala UI's 1.079 em, Mangal's 1.241. The line joiner of `_span`
                // raises the engine's line, but the correction above pulled the baseline back to the
                // Latin face's. dx2 b785c95e's Gujarati title: baseline 25.9 pt under the margin in
                // Word's print, ours 22.5.)
                var indicLift = 0.0
                if theme.wordRules, RichTextTheme.wordWindowsPages, style.lineHeightPoints == nil || style.lineHeightIsMinimum,
                   let raised = _indicFirstLineAscent(p, painter: painter, lead: _lead(i), named: named, document: document, target: target,
                                                      style: style, pitch: pitch, lift: &indicLift) {
                    target = raised
                    segoeLift = max(segoeLift, indicLift)
                }
                // (A first line holding a mark, digit or Latin letter that Word draws in Mangal, in a Tamil paragraph set in Noto Sans Tamil (a face Windows
                // lacks), stands on Mangal's 1.241 em ascent: xd c016493b's author lines, 3.1 pt higher in Word's print than the Nirmala line's.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, style.lineHeightPoints == nil, let mangal = Self._indicLines["mangal"],
                   let size = lead.0.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? Optional(theme.fontSize), !p.text.isEmpty,
                   _firstLineHoldsMangalMark(p, painter: painter, lead: _lead(i), named: named, document: document),
                   size * mangal.0 > target + 0.01 {
                    RuleTrace.hit("word-noto-sans-tamil-mark-stands-the-first-line-on-mangals-ascent")
                    target = size * mangal.0
                }
                // (A first line of Tamil letters alone in Noto Sans Tamil stands on Nirmala UI's 1.079 em, the face Word draws them in: ours stood
                // 1.4 pt higher on the Latin stand-in's; c016493b's "தமிழ் மேம்பாட்டுச் சங்கப்பலகை" line 1.2 pt high, the next 1.4 pt too far.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, style.lineHeightPoints == nil, let nirmala = Self._indicLines["nirmala ui"],
                   let size = lead.0.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? Optional(theme.fontSize), !p.text.isEmpty,
                   Self._markInMangal(lead.0.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "", p.text[...]),
                   !_firstLineHoldsMangalMark(p, painter: painter, lead: _lead(i), named: named, document: document),
                   size * nirmala.0 > target + 0.01 {
                    RuleTrace.hit("word-noto-sans-tamil-letters-stand-the-first-line-on-nirmalas-ascent")
                    target = size * nirmala.0
                }
                // (A first line of Myanmar letters under an "at least" line stands on Myanmar Text's own line, not on the Latin face's with the
                // minimum's extra above it: the line is the taller of the minimum and 1.861 em, the extra above the baseline. dx2 80bde9af's
                // 11 pt lines at least 20.1 pt: Word's first baseline 11.4 pt under the margin, ours 17.3.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, style.lineHeightIsMinimum, let least = style.lineHeightPoints,
                   !p.text.isEmpty, let size = lead.0.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? Optional(theme.fontSize),
                   String(p.text.prefix(max(0, painter.getLineBoundary(TextPosition(offset: 0)).end - _lead(i)))).unicodeScalars.contains(where: { $0.value >= 0x1000 && $0.value < 0x10A0 }) {
                    let up = size * 2122.0 / 2048, down = size * 1689.0 / 2048
                    RuleTrace.hit("word-myanmar-first-line-under-at-least-stands-on-myanmar-text")
                    target = max(least, up + down) - down
                }
                // (A first line holding a Malgun-drawn symbol of a missing Korean face: see `_koreanSymbolFirstLineRaise`.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, style.lineHeightPoints == nil,
                   let raise = _koreanSymbolFirstLineRaise(p, painter: painter, lead: _lead(i), named: named, document: document) {
                    target += raise
                }
                // (A first line of ASCII marks alone in a missing Bengali face (SolaimanLipi), in a document that has Bengali, is Mangal's line: under an "at least"
                // height the extra goes above the baseline only where Mangal's own height falls short of the minimum, so the baseline stands on Mangal's
                // ascent, not on the Latin face's under the minimum. xd 73caaeda's rule of dashes, 13.5 pt at least 22.5: Word's step into it 22.7, ours 24.9.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, style.lineHeightIsMinimum, let least = style.lineHeightPoints, let mangal = Self._indicLines["mangal"],
                   let size = lead.0.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? Optional(theme.fontSize), !p.text.isEmpty,
                   _asciiRunInMissingBengaliFace(lead.0, named, document, p.text[...], p.text) {
                    let stand = max(size * mangal.0, least - size * mangal.1)
                    if stand < target - 0.01 {
                        RuleTrace.hit("word-missing-bengali-face-marks-line-under-at-least-stands-on-mangal-ascent")
                        target = stand
                    }
                }
                // (A Wingdings bullet over Latin text at single spacing stands the first line on its own ascent, laid out so in `_span`
                // ("word-wingdings-bullet-at-single-stands-the-first-line-on-its-ascent"): the ink goes with it, in a one-line item as in a
                // wrapped one. The one-line items stood 0.8pt high, rows 0.6 to 0.8 above Word's print (sa1 5393bae9's 12pt bullets over 10pt Century Gothic).)
                if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, style.lineHeightPoints == nil, style.lineSpacing <= 1.001,
                   p.style.list == .bullet, !p.style.rightToLeft, _levelNumberFonts(p, document).latin?.lowercased() == "wingdings",
                   let ms = _markerChar(p, document).fontSize ?? lead.0.fontSize, ms > 0.5, ms * 1841.0 / 2048 > target + 0.01,
                   !p.text.unicodeScalars.contains(where: { ($0.value >= 0x590 && $0.value <= 0x8FF) || Self._isIndic($0.value) || ($0.value >= 0x2E80 && $0.value <= 0xFFEF) }) {
                    RuleTrace.hit("word-wingdings-bullet-at-single-ink-stands-on-the-bullet-ascent")
                    target = ms * 1841.0 / 2048
                }
                if _symbolBulletOnNaturalLine(p, painter: painter, style: style, document: document),
                   let ms = _markerChar(p, document).fontSize ?? lead.0.fontSize, ms * 1.005 > target {
                    RuleTrace.hit("word-symbol-bullet-line-at-a-line-multiple-stands-on-symbols-ascent")
                    target = ms * 1.005
                }
                _inkShift[i] = _px(target) - line.baseline
                // (A vertical ruby column on a grid is laid out as the tall column it is: the plain line's baseline is not its own,
                // and the column shift is applied at paint time per glyph (`vshift=`). Lab rgrid.)
                if _verticalBody(i), pitch != nil, style.lineHeightPoints == nil, p.runs.contains(where: { $0.style.ruby != nil }), _inkShift[i] < 0 {
                    _inkShift[i] = 0
                }
                // (A Wingdings 2 bullet's line is laid out on the mark's ascent (`_span`, "word-wingdings2-lowered-bullet..."),
                // but Word draws the row's ink as much lower as the bullet is lowered: lab bea-lab, rows 1.6 (3pt lowered 22pt boxes),
                // 3.0 (12pt) and 3.15pt (6pt lowering) under ours, the pitches and the table's foot equal. The text's baseline above
                // must not pull the line back to the text's ascent: dx2 bea98273's rows stood 8.7pt high.)
                if let half = _w2Half(), let boxPt = _markerChar(p, document).fontSize, boxPt > 0.5 {
                    let lowering = -half / 2 * theme.pixelsPerPoint * scale
                    let up = max(_px(boxPt) * 1727.0 / 2048 - lowering, _px(target))
                    RuleTrace.hit("word-wingdings2-bullet-row-ink-stands-lowered-under-its-line")
                    _inkShift[i] = up - line.baseline
                    // (The engine's line can stand higher than the line the bullet and the row set (the stand-in
                    // joiner of an Indic row): the row is as tall as that line, not the engine's: dx2 bea98273's
                    // Nirmala UI rows pitched 19.2pt on Word's 18.3.)
                    if line.baseline > up + 0.01, painter.computeLineMetrics().count == 1,
                       p.text.unicodeScalars.first(where: { $0.value != 0x20 }).map({ Self._isIndic($0.value) }) == true { w2Trim = line.baseline - up }
                    w2Done = true
                }
            }
        }
        }
        _blk5()
        // (… and a paragraph `_blk5` leaves alone stands on the mark's ascent already: its ink goes as much lower.)
        if !w2Done, let half = _w2Half(), half < 0, !p.text.isEmpty {
            RuleTrace.hit("word-wingdings2-bullet-row-ink-stands-lowered-under-its-line")
            // (The box alone stands lowered, in `_paintMarker`'s caller; the text keeps its baseline.)
        }
        // An empty numbered paragraph in a cell, on an exact line: its number stands where
        // the same line's text would, which is lower than the strut sets it
        // (zh-c97500b6's 1, 2, 3, 4: 6pt high).
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.text.isEmpty, p.image == nil, !p.runs.isEmpty, p.style.list != nil,
           i < _cells.count, _cells[i] != nil, let exact = p.style.lineHeightPoints, exact > 0, !p.style.lineHeightIsMinimum,
           let line = painter.computeLineMetrics().first {
            let named = _named(p, document)
            let pitch = _offGrid(i, document) ? nil : _grid(i, document).pitch
            if let target = theme.baseline(for: _markerChar(p, document), in: style, named: named, eastAsian: true, gridPitch: pitch, centresInLine: document.spacesForUnderline) {
                RuleTrace.hit("word-empty-list-item-number-on-the-exact-line-baseline")
                _inkShift[i] = _px(target) - line.baseline
            }
        }
        // Over single spacing Word puts all of a line's extra height under its text, so a
        // line with a taller run in it stands on that run's own ascent from the line's top.
        // The engine scales every run's box and puts the baseline at the tallest run's
        // scaled ascent: the first line's correction (`_inkShift`) is right for lines
        // like it and leaves a taller one low by the difference of the scaled parts. Each
        // such line is drawn lifted by its own shift (`_paintShiftedLines`). (lo-52da6bc6:
        // 6.0 lines, a 44pt word in the third, which Word's print has 148pt higher than ours.)
        _lineLift[i] = []
        if mixedSizes, theme.wordRules, RichTextTheme.wordWindowsPages,
           painter.strutStyle == nil, p.inlineImages.isEmpty, p.image == nil, style.lineHeightPoints == nil,
           p.runs.allSatisfy({ $0.style.script == .normal }),
           theme.lineSpacingReduction == 0, style.lineSpacing > 1.05 {
            let metrics = painter.computeLineMetrics()
            let lift = metrics.map { -(1 - 1 / style.lineSpacing) * ($0.ascent - metrics[0].ascent) }
            if metrics.count > 1, lift.contains(where: { abs($0) > _px(0.05) }) {
                RuleTrace.hit("word-multiple-spacing-puts-the-extra-under-the-tallest-run-of-each-line")
                _lineLift[i] = lift
            }
        }
        // Word splits the extra height of a Malgun-symbol line (○ · ① ※ curly quotes) the same on EVERY line
        // that holds one, not on the first alone: the symbol face's taller ascent sits over the text, and the
        // plain Batang lines of the paragraph stand 0.41 x (the ascents' difference) higher than the engine,
        // which scales every line by its own tallest run, draws them (xd 4fabe1f2 p4: ① ② ⑤ lines 0.9-1.9pt low).
        if theme.wordRules, RichTextTheme.wordWindowsPages,
           painter.strutStyle == nil, p.inlineImages.isEmpty, p.image == nil, p.cell == nil, style.lineHeightPoints == nil,
           theme.lineSpacingReduction == 0, style.lineSpacing > 1.05, p.text.utf16.count > 1 {
            let flags = _koreanSymbolLineFlags(p, painter: painter, lead: _lead(i), named: _named(p, document), document: document)
            let metrics = painter.computeLineMetrics()
            if flags.count == metrics.count, metrics.count > 1, flags.contains(true) {
                let top = metrics.map { $0.ascent }.max() ?? 0
                // (Measured on xd 4fabe1f2 at 12pt, 1.7 lines: a plain line whose ascent is Batang's stands 0.8pt
                // higher in Word's print than the engine's, one the symbol face's ascent made as tall as a symbol
                // line 1.9pt: lift = -0.158 em + (1 - 1/spacing) x (the tallest line's ascent - its own).)
                let size = p.runs.first.flatMap { $0.style.fontSize } ?? _named(p, document)?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                let held = _lineLift[i].count == metrics.count ? _lineLift[i] : []
                let lift = metrics.enumerated().map { k, m in
                    k == 0 || flags[k] ? (held.isEmpty ? 0 : held[k]) : -_px(0.158 * size) + (held.isEmpty ? (1 - 1 / style.lineSpacing) * (top - m.ascent) : held[k])
                }
                if lift.contains(where: { abs($0) > _px(0.05) }) {
                    RuleTrace.hit("word-korean-symbol-lines-share-the-extra-height-on-every-line")
                    _lineLift[i] = lift
                }
            }
        }
        // A line whose every character Word sets in a shorter face of the fallback chain
        // (zh-5450d509's last line "引》）。": MS Gothic, no JhengHei ideograph on it) stands
        // on that face's baseline under the line's top, not the paragraph's: Word's lab
        // (gothic-last, 1.5 lines on a grid) has it 4.6pt higher, the line as tall as the others.
        @inline(never) func _blk6() {
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.image == nil, p.inlineImages.isEmpty, p.cell == nil,
           !p.text.isEmpty, painter.strutStyle != nil,
           p.runs.allSatisfy({ $0.style.script == .normal }), _lineLift[i].isEmpty {
            let pitch = _offGrid(i, document) ? nil : _grid(i, document).pitch
            let named = _named(p, document)
            let units = Array(p.text.utf16)
            // Each UTF-16 unit's chain face (nil: covered by the subset, or no ideograph).
            var faceAt = [String?](repeating: nil, count: units.count)
            var freshAt = [String?](repeating: nil, count: units.count)  // the face with no carry-over from the character before
            var start = 0
            var chained = false
            for run in p.runs where run.length > 0 {
                defer { start += run.length }
                guard let face = theme.faceResolver?(run.style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily
                                                     ?? _normalChar(document)?.eastAsiaFontFamily ?? run.style.fontFamily
                                                     ?? named?.char.fontFamily ?? theme.fontFamily, true),
                      let covers = face.covers, let chain = face.uncoveredChain else { continue }
                var k = start
                var sticky: Int? = nil
                for ch in String(decoding: units[start ..< min(start + run.length, units.count)], as: UTF16.self) {
                    let n = String(ch).utf16.count
                    if let u = ch.unicodeScalars.first?.value, u >= 0x2E80, u != 0xFFFC {
                        if covers.contains(u) { sticky = nil } else {
                            // (As the first line's scan: a run keeps its face while that face holds the next character.)
                            if let at = sticky, chain[at].covers?.contains(u) ?? true {} else { sticky = chain.firstIndex { $0.covers?.contains(u) ?? true } ?? chain.count - 1 }
                            for j in k ..< min(k + n, units.count) { faceAt[j] = chain[sticky!].family }
                            let fresh = chain.firstIndex { $0.covers?.contains(u) ?? true } ?? chain.count - 1
                            for j in k ..< min(k + n, units.count) { freshAt[j] = chain[fresh].family }
                            chained = true
                        }
                    }
                    k += n
                }
            }
            if chained {
                var tops: [Double] = []
                var shortLast = false
                var from = 0
                var run0 = p.runs[0].style
                while from < units.count {
                    let end = max(from + 1, painter.getLineBoundary(TextPosition(offset: from + _lead(i))).end - _lead(i))
                    var best = -Double.infinity
                    var seen = Set<String>()
                    for j in from ..< min(end, units.count) {
                        guard let fam = (end >= units.count ? freshAt[j] : faceAt[j]), seen.insert(fam).inserted else { continue }
                        var r = run0
                        r.eastAsiaFontFamily = fam
                        if let b = theme.baseline(for: r, in: style, named: named, eastAsian: true, gridPitch: pitch, centresInLine: document.spacesForUnderline) { best = max(best, b) }
                    }
                    // (A character the subset holds sets none: Word's "）" there stood with the rest.)
                    // (Only a short last line — the lab's four characters: a longer line of
                    // characters our cmap says MS Gothic holds is JhengHei's in Word's print.)
                    tops.append(best)
                    shortLast = end >= units.count && end - from <= 5
                    from = end
                    run0 = p.runs[0].style
                }
                        if tops.count > 1, let first = tops.first, first.isFinite {
                    let lift = tops.enumerated().map { k, t in shortLast && k == tops.count - 1 && t.isFinite && t < first - 0.05 ? t - first : 0 }
                    if lift.contains(where: { $0 != 0 }) {
                        RuleTrace.hit("zh-5450d509-a-line-of-the-shorter-chain-face-stands-on-its-baseline")
                        _lineLift[i] = lift.map { _px($0) }
                    }
                }
            }
        }
        }
        _blk6()
        // (The number's lift sets the first baseline no higher than the
        // layout without the strut does, over whatever baseline the text
        // was given above — not on top of it: zh-76700e5f's "5.3 制棒"
        // headings stood a point under Word's with both.)
        // (A bullet in Symbol stands the first line on Symbol's own ascent under its top, where that is more than
        // the text's, and the line as much taller — Word for Windows: LibreOffice's tdf104492, Arial 10pt under a "•", has
        // its bullet lines 12.25pt (1.225 em, Symbol's 1005 and 220 of 1000) apart where the others are Arial's 11.5; Times 12pt
        // goes 13.8 to 14.7. Courier New's "o" (0.833 over the baseline) sets nothing, nor does Calibri, whose own is the taller.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.list == .bullet, p.image == nil, !p.text.isEmpty,
           style.lineHeightPoints == nil || style.lineHeightIsMinimum,
           _levelNumberFonts(p, document).latin?.lowercased() == "symbol",
           let line = painter.computeLineMetrics().first {
            let named = _named(p, document)
            // (A mark of no size of its own is the paragraph style's, not the first run's — and a bullet so set larger than
            // the text stands the line's first baseline 0.12 em more than its ascent under the top: lo-717ff943's
            // 10pt lines under Normal's 11pt, 12.33pt to the baseline in Word's print where 10pt ones are 11.39.)
            let ownMark = _markerChar(p, document).fontSize
            let styleSize = named?.char.fontSize ?? _normalChar(document)?.fontSize
            let larger = ownMark == nil && p.style.mark != nil && (styleSize ?? 0) > (p.runs[0].style.fontSize ?? .infinity) + 0.01
            // (A mark of no size under a style SMALLER than the text is the style's too: lab bullet-mark, 9pt bullets over 12pt text, the first row 0.92pt low.)
            let smaller = ownMark == nil && p.style.mark != nil && (styleSize ?? .infinity) < (p.runs[0].style.fontSize ?? 0) - 0.01
            let markerSize = ownMark ?? ((larger || smaller) ? styleSize : nil) ?? p.runs[0].style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
            let need = _px(markerSize * (larger ? 1.125 : 1.005)) - line.baseline
            // (At a line multiple the text's own shift may already stand the extra UNDER the text, up from the painter's baseline; Symbol's ascent
            // is then judged against that stood baseline: Calibri 12pt at 1.15 stands 11.43, Symbol 12.06, and sa1 5e813226 p37's first bullet was 0.63pt high.)
            if need > _px(0.05) || (_inkShift[i] < 0 && need > _inkShift[i] + _px(0.05)) {
                _inkShift[i] += max(0, need - _inkShift[i])
                // (A bullet that carries its own size stands on its ascent and adds none below, as the lead box does for it: the line's foot
                // is the text's, 14.4pt apart for a 12pt bold Symbol dash over Arial 11 where 1.225 em made 14.7: xb fra-g111-8b0e29.)
                var tall = ownMark != nil && !larger ? need + line.baseline + line.descent : _px(markerSize * 1.225)
                // (A line the strut already stands on Symbol's ascent over the text's descent (see `_span`) is Word's pitch as it is, 12.17 pt for Arial 10, not the face's whole 1.225 em.)
                if !larger, ownMark == nil, style.lineSpacing <= 1.001, line.height >= _px(markerSize * 1.2) { tall = line.height }
                // (Under a line multiple below one the Symbol bullet's line is scaled with the text's: dx2 fa 6e7a3d11's 10pt bullet items at 0.8
                // step 9.96 pt in Word's print, 0.8 of Symbol's 12.45, where the lift stood unscaled on the squeezed line made 11.9.)
                if style.lineSpacing < 0.999 { tall *= style.lineSpacing }
                segoeLift += max(0, tall - line.height) / _px(1)
            }
        }
        // (On a line grid the first line is as tall as its list number makes it too, where the number's own
        // line is more pitches than the text's: the "7．" of xb jpn 771abc's "7．まとめと残された課題", an 11pt
        // bold number over 10.5pt text, is a line of two pitches, 35.9pt to the next baseline in Word's print,
        // where the text alone makes one and ours were 27.3. The text keeps its baseline; the foot is lower.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.list != nil, p.image == nil, !p.text.isEmpty,
           style.lineHeightPoints == nil || style.lineHeightIsMinimum, !_offGrid(i, document), let gridPitch = _grid(i, document).pitch,
           let label = listLabel(i, document), !label.isEmpty,
           label.contains(where: { Self.isEastAsian($0, hinted: true) }),
           !["symbol", "wingdings", "wingdings 2", "wingdings 3", "webdings"].contains(_levelNumberFonts(p, document).latin?.lowercased() ?? ""),
           let line = painter.computeLineMetrics().first {
            let mark = _markerChar(p, document)
            if let natural = theme.naturalLine(for: mark, named: _named(p, document), eastAsian: true), natural > gridPitch + 0.01,
               // (Only where the number's line is more pitches than the text's own: a 16pt number over 16pt text is the text's line already.)
               let first = p.runs.first, let textNatural = theme.naturalLine(for: first.style, named: _named(p, document), eastAsian: true),
               (natural / gridPitch).rounded(.up) > (textNatural / gridPitch).rounded(.up) {
                let want = _px((natural / gridPitch).rounded(.up) * gridPitch)
                if want > line.height + _px(0.5) {
                    RuleTrace.hit("word-grid-first-line-is-as-tall-as-its-number")
                    segoeLift += (want - line.height) / 2 / _px(1)
                    let n = painter.computeLineMetrics().count
                    if n > 1 {
                        var lift = _lineLift[i]
                        if lift.count < n { lift += Array(repeating: 0, count: n - lift.count) }
                        for k in 1 ..< n { lift[k] += (want - line.height) / 2 }
                        _lineLift[i] = lift
                    }
                }
            }
        }
        // (A first line under a Hebrew or Arabic-letter number is as tall as the number's face makes it: xd b9164bf3's David 12pt lines
        // at 1.5 step 17.7, the lines opened by a bold Times New Roman "א." 19.9, 1.107 em by the multiple.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.image == nil, !p.text.isEmpty, style.lineHeightPoints == nil,
           // (Or a counted number whose level names only a complex-script face, as `_markerChar` draws it: xd ba3e11e2's "1." items,
           // a w:cs Times New Roman level over David 12pt lines, step 26.0 at 1.5 with their 6pt before where David's step 23.7.)
           (p.style.listId.flatMap({ document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.rawFormat })
               .map({ $0.hasPrefix("hebrew") || $0.hasPrefix("arabic") }) ?? false
            || (p.style.list == .numbered && _markerChar(p, document).complexFontFamily?.trimmingWhitespace().lowercased() == "times new roman"
                && _levelNumberFonts(p, document).latin == nil)),
           let face = _levelNumberFonts(p, document).latin ?? _markerChar(p, document).complexFontFamily, face.trimmingWhitespace().lowercased() == "times new roman",
           let nat = Optional(2268.0 / 2048.0),   // (Windows Times New Roman: 1825 ascent, 443 descent of 2048)
           let line = painter.computeLineMetrics().first {
            let named = _named(p, document)
            let size = _levelNumberSize(p, document) ?? _markerChar(p, document).fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
            let h = _px(size * nat) * style.lineSpacing
            if h > line.height + _px(0.05) {
                RuleTrace.hit("word-hebrew-number-face-lifts-the-first-line")
                segoeLift += (h - line.height) / _px(1)
            }
        }
        if numberLift > 0.001 {
            // (An ink shift already UP, negative, is no part of a BULLET's lift: only a shift down covers it. A counted number's
            // lift stands over it: xb a567c5c2's 20pt "1." over 11pt text at 1.5 lines.)
            let bulletOnly = !(p.style.listId.flatMap { document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.text }?.containsSubstring("%") ?? false)
            let extra = max(0, numberLift - (bulletOnly ? max(0, _inkShift[i]) : _inkShift[i]))
            _inkShift[i] += extra
            _numberLiftShift[i] = extra
            segoeLift += extra / _px(1)
        }
        // (A list number in a face that stands taller above its baseline than the text's, over a line at a multiple: Word draws the first line on the
        // text's own unscaled ascent, the multiple's extra under it, and adds the number's excess over the text's ascent ABOVE it, not multiplied
        // by the multiple. Lab lblcal1/lblcal2 A (Calibri 11 "1)" over Times New Roman 11 at 1.079 lines): items 13.9 apart where plain ones are 13.68,
        // the first baseline 21.7 under the line above, 21.6 for a plain one. The engine, its strut dropped for the number's box, drew the baseline
        // at the multiple's scaled ascent, 0.7 pt low, and grew nothing.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.list != nil, p.image == nil, !p.text.isEmpty, painter.strutStyle == nil,
           style.lineHeightPoints == nil, style.lineSpacing > 1.001, _inkShift[i] == 0, numberLift == 0,
           let g = _labelFaceGrowth(p, named: _named(p, document), document: document, style: style),
           let line = painter.computeLineMetrics().first {
            RuleTrace.hit("word-number-face-taller-over-a-multiple-adds-its-excess-above-the-unscaled-text-ascent")
            _inkShift[i] = _px(g.target) - line.baseline + _px(g.growth)
            segoeLift += g.growth
        }
        @inline(never) func _blk7() {
        if i < _overhang.count {
            _overhang[i] = 0
            if i < _lineOverhang.count { _lineOverhang[i] = [] }
            // (A picture's paragraph has no overhang, whatever floats are anchored in
                // it: a wrapNone text box beside one tall inline picture made the picture
                // look like text, and its 37pt allowance kept it 12pt past page 1's foot
                // where Word starts page 2 with it: sa2 a7546bac.)
                let loneInline = theme.wordRules && RichTextTheme.wordWindowsPages && _inlinePictureOnly(i, document)
                    && p.inlineImages.values.filter { $0.float == nil && $0.textBox == nil }.count == 1
                if theme.wordRules, p.image == nil, !loneInline, p.cell == nil, style.eastAsian["w:snapToGrid"] != "0", let pitch = _grid(i, document).pitch {
                let named = _named(p, document)
                // (An empty paragraph's line is its mark's, and the mark
                // has two faces: its overhang is the smaller of theirs —
                // the half leading the taller face leaves. zh-64044a1d's
                // empty Body Text marks, 12pt 標楷體 over Times, are one
                // 18pt pitch; the East Asian face's own box would be two,
                // and its 7.7pt overhang let ours keep a fourteenth on page
                // 97 where Word's print keeps thirteen. zh-6d1afa56's 14pt
                // mark, Times over 方正小标宋, is two 15.6pt pitches either
                // way, and Times' 7.55 sent the page break after it onto a
                // blank page; the East Asian face's 3.6 keeps Word's.)
                let look = p.text.isEmpty ? (style.mark ?? p.runs.first?.style ?? CharStyle()) : p.runs[0].style
                if p.text.isEmpty {
                    // (Word's lab `ec`: an empty line's allowance is its Latin face's — Times over
                    // 16pt 標楷體 on a 36pt line hangs 8.8, 14pt 7.5 on 31.2, 12pt 2.1 on 18 —
                    // when the East Asian face is 標楷體, which the lab had. Others, whose natural
                    // height the lab could not measure (方正小标宋 was not installed; zh-6d1afa56's
                    // 14pt marks on 15.6 keep Word's page break only at the least of both): the least.)
                    let latinOverhang = theme.gridOverhang(for: look, in: style, named: named, eastAsian: false, gridPitch: pitch)
                    _overhang[i] = _px((look.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? "").containsSubstring("標楷")
                        ? latinOverhang
                        : min(theme.gridOverhang(for: look, in: style, named: named, eastAsian: true, gridPitch: pitch), latinOverhang))
                } else {
                    // (By the deepest face on the line, not the first run's:
                    // the foot must reach each face's natural line under the
                    // baseline — lab `footlab` (Word 16): 0.294 em in 宋体,
                    // 0.465 in the YaHei Word sets 仿宋_GB2312 in. zh-17749c13's
                    // "第六十六条…" is 宋体 bold and then YaHei, and its 宋体
                    // first run's 6.5pt let ours keep at page 20's foot a line
                    // Word sends over.)
                    // (… and on the line that ends the page, by that line's
                    // faces alone: zh-c15af02e's p11 paragraph has a "%" in
                    // 新細明體 on its second line, whose one pitch leaves 1pt,
                    // and its fifteenth line, all 標楷體 in two pitches, ends
                    // 5.4pt past the foot and is page 11's last in Word's
                    // print; ours, taking the 1pt for every line, sent it on.)
                    var least = Double.infinity
                    var at = p.text.startIndex
                    var offset = 0
                    let map = _OffsetMap(lead: _lead(i), inserts: i < _inserts.count ? _inserts[i] : [])
                    let tops = painter.computeLineMetrics().map { $0.baseline - $0.ascent }
                    // (The line an offset's caret stands on.)
                    func lineOf(_ offset: Int) -> Int {
                        let dy = painter.getOffsetForCaret(TextPosition(offset: map.painter(offset)), Rect.zero).dy
                        return max(0, (tops.lastIndex { $0 <= dy + 0.5 }) ?? 0)
                    }
                    var perLine = Array(repeating: Double.infinity, count: tops.count)
                    for run in p.runs {
                        let end = p.text.utf16.index(at, offsetBy: run.length, limitedBy: p.text.endIndex) ?? p.text.endIndex
                        let text = p.text[at ..< end]
                        at = end
                        let from = offset
                        offset += run.length
                        guard text.contains(where: { !$0.isWhitespace }) else { continue }
                        let ea = text.contains { Self.isEastAsian($0, hinted: false) }
                        let reach = theme.gridOverhang(for: run.style, in: style, named: named, eastAsian: ea, gridPitch: pitch)
                        least = min(least, reach)
                        if !perLine.isEmpty {
                            for k in min(lineOf(from), perLine.count - 1) ... min(max(lineOf(from), lineOf(offset - 1)), perLine.count - 1) {
                                perLine[k] = min(perLine[k], reach)
                            }
                        }
                    }
                    if !least.isFinite {
                        let ea = p.text.contains { Self.isEastAsian($0, hinted: false) }
                        least = theme.gridOverhang(for: look, in: style, named: named, eastAsian: ea, gridPitch: pitch)
                    }
                    _overhang[i] = _px(least)
                    if i < _lineOverhang.count, perLine.count > 1 { _lineOverhang[i] = perLine.map { _px($0.isFinite ? $0 : least) } }
                }
            } else if theme.wordRules, document.suppressBottomSpacing, p.image == nil, p.cell == nil,
                      let exact = style.lineHeightPoints, !style.lineHeightIsMinimum,
                      let natural = theme.naturalLine(for: p.text.isEmpty ? (style.mark ?? p.runs.first?.style ?? CharStyle()) : p.runs[0].style, named: _named(p, document), eastAsian: false), exact > natural {
                // (Under `w:suppressBottomSpacing` an exact line stays at the
                // page's foot while its face's own height fits: what the
                // exact height holds under the text may hang past it. Lab
                // sbs, Arial 10 in 30, 20 and 30-plus-after exact lines:
                // kept at 11.9pt of room, sent on at 10.9; without the
                // flag they need the whole 30.9 / 20.9.)
                RuleTrace.hit("word-suppressbottomspacing-lets-an-exact-line-hang-past-the-foot")
                _overhang[i] = _px(exact - natural)
            } else if theme.wordRules, RichTextTheme.wordWindowsPages, p.cell == nil, style.lineHeightPoints == nil,
                      p.image != nil || _inlinePictureOnly(i, document),
                      case let multiple = style.lineSpacing - theme.lineSpacingReduction, multiple > 1.001 {
                // (A picture's line under a multiple: the extra stands under the picture, (m - 1) of the
                // mark's single line, and may hang past the foot as a text line's does. sa2 ab55f8b0's
                // pie chart, 306.55pt in a 1.5-spaced paragraph, ends 0.7pt past the text foot and
                // stays on page 3 in Word's print; ours sent it to page 4.)
                RuleTrace.hit("word-picture-line-multiple-extra-hangs-past-the-foot")
                _overhang[i] = (multiple - 1) * _markLineHeight(i, document, single: true)
            } else if theme.wordRules, p.image == nil, p.cell == nil, style.lineHeightPoints == nil,
                      case let multiple = style.lineSpacing - theme.lineSpacingReduction, multiple > 1.001,
                      let last = painter.computeLineMetrics().last {
                // (Off the grid, a multiple's extra stands under the text,
                // and the page's last line may reach past the foot by it:
                // zh-8112041b's page 2 keeps four empty 1.5-spaced 16pt
                // paragraphs under its articles in Word's print, the
                // fourth's 36pt line 5pt over the margin and its 24 of
                // text inside it.)
                // (Of the line's advance where the paragraph keeps its
                // lines' fractions: on the Mac a 1.5-spaced YaHei line's
                // ascent and descent are 644.8 of an advance of 617.4,
                // and the larger third let zh-34a6519a's "（3）依法实施"
                // onto page 5 with 0.5 to spare where Word's goes on.)
                let height = painter.fractionalLineHeights ? painter.computeLineAdvances().last ?? last.height : last.height
                // (A paragraph whose lines hold a taller Latin run's extra
                // below the baseline keeps no forgiven overhang: fas-768d17's
                // bullet, baseline 717.4 + Arial descent 2.54 + Aptos 0.9 =
                // 720.8, goes to the next page in Word's print.)
                _overhang[i] = _heldTallerLatin.contains(i) ? 0.001 : height * (1 - 1 / multiple)
            }
        }
        }
        _blk7()
        // (A box the text keeps above and below, standing part way down the paragraph that
        // holds its anchor: the lines that would meet it go under it — Word's print of
        // LibreOffice's tdf133924, "notBeside" 273pt down a paragraph of text.)
        var keepClear: (top: Double, bottom: Double)?
        // (One column only: in several the paragraph's lines are cut into columns, and the
        // existing placement of a band keeps them off — lo shape-anchored-in-follow.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.cell == nil, !p.text.isEmpty, !style.rightToLeft, _columns <= 1 {
            for image in p.inlineImages.inOrder {
                guard let float = image.float, float.takesRoom || float.bandsPage, !float.wraps, float.verticalAlign == nil, float.verticalFrom == "paragraph", float.y > 0 else { continue }
                keepClear = (_px(float.y - float.distanceTop), _px(float.y + image.height + float.effectBottom + float.distanceBottom))
                break
            }
        }
        if theme.wordRules, RichTextTheme.wordWindowsPages, _columns > 1, p.cell == nil, let band = _clearBand[i] { keepClear = band }
        // (An equation taller than the text in a 1.5-line paragraph: Word applies the multiple to the line's
        // tallest content, so the line is 1.5 times the equation's own height where the strut holds it to 1.5
        // times the text's. Word's print of jpn-z22855378-6fca0f: a line with a 17.0 over 7.9pt fraction is 36pt,
        // the others 27. The lines are held to the strut here and the taller one is drawn lower, with those
        // after it: the extra above the baseline is what the equation stands higher than the text's own.)
        let wholePitchEquation = inline.contains { $0.image?.name == "m:oMath" && $0.image?.float == nil && _pageFill[$0.image?.id ?? ""] != nil }
        if equationLinesGrowAfterLayout, !wholePitchEquation, painter.strutStyle?.forceStrutHeight == true, keepClear == nil, Self._paired(painter) == nil,
           let boxes = painter.inlinePlaceholderBoxes, boxes.count == inline.count, !boxes.isEmpty {
            let bottoms = Self._rawLineBottoms(painter)
            let metrics = painter.computeLineMetrics()
            var extra = [Double](repeating: 0, count: bottoms.count), above = extra
            for (k, box) in boxes.enumerated() {
                guard let whole = inline[k].image?.naturalExtent, inline[k].image?.name == "m:oMath", inline[k].image?.stackedEquation == true else { continue }
                let mid = box.toRect().top + box.toRect().height / 2
                guard let line = bottoms.firstIndex(where: { mid < $0 }), line < metrics.count else { continue }
                let before = line == 0 ? 0 : bottoms[line - 1], advance = bottoms[line] - before
                let target = style.lineSpacing * _px(whole.ascent + whole.descent)
                guard target > advance + 0.01 else { continue }
                // Word sets the equation centred in its taller line: the gap above and below it is equal.
                let eqHeight = _px(whole.ascent + whole.descent)
                let newBase = (target - eqHeight) / 2 + _px(whole.ascent)
                let reach = max(0, newBase - (metrics[line].baseline - before))
                extra[line] = max(extra[line], target - advance)
                above[line] = max(above[line], min(reach, extra[line]))
            }
            if extra.contains(where: { $0 > 0 }) {
                RuleTrace.hit("word-an-equation-line-of-multiple-spacing-is-the-multiple-of-the-equation")
                var shifts = [Double](repeating: 0, count: bottoms.count)
                var acc = 0.0
                for k in 0 ..< bottoms.count {
                    shifts[k] = acc + above[k]
                    acc += extra[k]
                }
                Self._pairedLines[ObjectIdentifier(painter)] = _PairedLines(painter: painter, shifts: shifts, saving: -acc)
            }
        }
        // (A tall equation on a line grid: Word's line is the equation's whole pitches (20d9968b's (1-r^n)/(1-r)^2 is two pitches, 36pt,
        // with the baseline 23.7 down it); the forced strut holds ours to one pitch and the box stands above the paragraph.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.cell == nil, !style.rightToLeft, _columns <= 1, painter.strutStyle?.forceStrutHeight == true,
           keepClear == nil, besideLineIndents.isEmpty, Self._paired(painter) == nil,
           let boxes = painter.inlinePlaceholderBoxes, boxes.count == inline.count, !boxes.isEmpty {
            let bottoms = Self._rawLineBottoms(painter)
            var above = [Double](repeating: 0, count: bottoms.count), below = above
            for (k, box) in boxes.enumerated() {
                guard let image = inline[k].image, image.name == "m:oMath", image.float == nil, _pageFill[image.id] != nil else { continue }
                let r = box.toRect()
                let mid = r.top + r.height / 2
                guard let line = bottoms.firstIndex(where: { mid < $0 }) else { continue }
                let before = line == 0 ? 0 : bottoms[line - 1]
                // (The extra is shared evenly above and below the strut's own line: the baseline stands half the extra lower, 21.8pt down a 36pt line.)
                let grow = max(0, r.height - (bottoms[line] - before)) / 2
                above[line] = max(above[line], grow)
                below[line] = max(below[line], grow)
            }
            if above.contains(where: { $0 > 0.01 }) || below.contains(where: { $0 > 0.01 }) {
                RuleTrace.hit("word-a-tall-equation-line-on-a-grid-is-its-whole-pitches")
                var shifts = [Double](repeating: 0, count: bottoms.count)
                var acc = 0.0
                for k in 0 ..< bottoms.count {
                    shifts[k] = acc + max(0, above[k])
                    acc += max(0, above[k]) + max(0, below[k])
                }
                Self._pairedLines[ObjectIdentifier(painter)] = _PairedLines(painter: painter, shifts: shifts, saving: -acc)
            }
        }
        // (A fraction in a line of "at least" spacing: Word's line is as tall as the text's strut or the fraction's own
        // ascent over the last line's foot, whichever is more: the gap from one baseline to the next is the larger of
        // the strut and the line above's descent plus this line's ascent. Lab frac3 case 10, 14pt at least, 11pt text and
        // fraction: 16.34 and 16.68 where the lines were all 14.0.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.cell == nil, !p.text.isEmpty, !style.rightToLeft, _columns <= 1,
           (style.lineHeightIsMinimum && (style.lineHeightPoints ?? 0) > 0 || style.lineHeightPoints == nil && abs(style.lineSpacing - 1) < 0.001), keepClear == nil, besideLineIndents.isEmpty,
           Self._paired(painter) == nil, let boxes = painter.inlinePlaceholderBoxes, boxes.count == inline.count, !boxes.isEmpty {
            let bottoms = Self._rawLineBottoms(painter)
            let metrics = painter.computeLineMetrics()
            if bottoms.count == metrics.count, bottoms.count > 1 {
                let textDescent = metrics.map { $0.descent }
                var ascent = [Double](repeating: 0, count: bottoms.count), descent = ascent
                for (k, box) in boxes.enumerated() {
                    guard let whole = inline[k].image?.naturalExtent, inline[k].image?.name == "m:oMath", inline[k].image?.stackedEquation == true else { continue }
                    let mid = box.toRect().top + box.toRect().height / 2
                    guard let line = bottoms.firstIndex(where: { mid < $0 }) else { continue }
                    // (Cambria Math's own extent is 0.077 em over Word's above and 0.15 em under the fraction's: lab frac3, 11pt.)
                    let em = painter.strutStyle?.fontSize ?? _px(11)
                    ascent[line] = max(ascent[line], _px(whole.ascent) - 0.077 * em); descent[line] = max(descent[line], _px(whole.descent) - 0.15 * em)
                }
                var extra = [Double](repeating: 0, count: bottoms.count)
                for line in 1 ..< bottoms.count {
                    let advance = bottoms[line] - bottoms[line - 1]
                    let tD = textDescent[line - 1]
                    let a = max(ascent[line], style.lineHeightPoints == nil ? metrics[line].baseline - bottoms[line - 1] : advance - tD)
                    let want = max(advance, max(descent[line - 1], tD) + a)
                    // (At single spacing the line after a bigger run already stands that run's descent under it: the gap to beat is the natural one.)
                    let held = style.lineHeightPoints == nil ? max(advance, tD + metrics[line].baseline - bottoms[line - 1]) : advance
                    if want > held + 0.01 { extra[line] = want - held }
                }
                if extra.contains(where: { $0 > 0 }) {
                    RuleTrace.hit("word-a-fraction-in-at-least-spacing-takes-its-own-ascent-and-descent")
                    var shifts = [Double](repeating: 0, count: bottoms.count)
                    var acc = 0.0
                    for k in 0 ..< bottoms.count { acc += extra[k]; shifts[k] = acc }
                    Self._pairedLines[ObjectIdentifier(painter)] = _PairedLines(painter: painter, shifts: shifts, saving: -acc)
                }
            }
        }
        // (A raised or lowered picture or object in a line of "at least" spacing: Word's line is the text's ascent or the
        // object's top, over the text's descent or the object's foot, and the minimum only when that is less. The engine's
        // strut had added the minimum's extra over the text's own line above the baseline first, so a line already taller
        // than the minimum stood that extra too tall. sa1 7de651e7 p6: a 15 pt object at -5 pt in 11 pt Calibri at least
        // 14 pt, 0.57 pt, every line after it that far low in Word's print.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.cell == nil, _columns <= 1, !style.rightToLeft,
           style.lineHeightIsMinimum, let least = style.lineHeightPoints, least > 0, keepClear == nil, besideLineIndents.isEmpty,
           Self._paired(painter) == nil, !p.text.isEmpty, let boxes = painter.inlinePlaceholderBoxes, boxes.count == inline.count, !boxes.isEmpty {
            let bottoms = Self._rawLineBottoms(painter)
            let metrics = painter.computeLineMetrics()
            var root = painter.text as? TextSpan
            func firstStyle(_ span: TextSpan, _ inherited: Flutter.TextStyle) -> Flutter.TextStyle? {
                let own = inherited.merge(span.style)
                if let tx = span.text, tx.contains(where: { !$0.isWhitespace && $0 != "\u{FFFC}" }) { return own }
                for c in span.children ?? [] { if let t = c as? TextSpan, let f = firstStyle(t, own) { return f } }
                return nil
            }
            if bottoms.count == metrics.count, !bottoms.isEmpty, let rootSpan = root, let ts = firstStyle(rootSpan, Flutter.TextStyle()) {
                root = nil
                let probe = TextPainter(text: TextSpan(text: "x", style: ts.copyWith(height: nil)), textDirection: .ltr)
                probe.layout(minWidth: 0, maxWidth: 10000)
                let own = probe.computeLineMetrics().first
                probe.dispose()
                let faceName = ts.debugLabel.flatMap { label -> String? in
                    label.split(separator: "(").compactMap { part -> String? in
                        guard let end = part.firstIndex(of: ")") else { return nil }
                        let n = String(part[part.startIndex ..< end])
                        return n.isEmpty || n == "unknown" ? nil : n
                    }.last
                }
                if let own, own.height > 0.5, let name = faceName, let share = theme.winDescent?(name) {
                    // (Word's own line of the face is its win line; the engine's probe line can differ)
                    let wordLine = theme.winLineBox?(name).flatMap { b in ts.fontSize.map { $0 * b } } ?? own.height
                    let tD = wordLine * share, tA = wordLine - tD
                    var above = [Double](repeating: -1, count: bottoms.count), below = above
                    for (k, box) in boxes.enumerated() {
                        guard let img = inline[k].image, img.float == nil, img.textBox == nil, img.name != "m:oMath" else { continue }
                        let pos = p.runs.first(where: { $0.style.inlineImage == img.id }).flatMap { $0.style.raised } ?? Self._runPosition(img.sourceRunPropertiesXML) ?? 0
                        guard abs(pos) > 0.01 else { continue }
                        let r = box.toRect()
                        guard let line = bottoms.firstIndex(where: { r.top + r.height / 2 < $0 }) else { continue }
                        above[line] = max(above[line], metrics[line].baseline - r.top)
                        below[line] = max(below[line], r.bottom - metrics[line].baseline)
                    }
                    var shifts = [Double](repeating: 0, count: bottoms.count)
                    var acc = 0.0
                    for line in 0 ..< bottoms.count {
                        if above[line] >= 0 {
                            let advance = bottoms[line] - (line == 0 ? 0 : bottoms[line - 1])
                            let word = max(_px(least), max(tA, above[line]) + max(tD, below[line]))
                            if advance > word + 0.01, advance - word < _px(least) * 0.1 { acc -= advance - word }
                        }
                        shifts[line] = acc
                    }
                    if acc < -0.01 {
                        RuleTrace.hit("word-a-lowered-object-in-at-least-spacing-takes-no-extra-over-the-minimum")
                        Self._pairedLines[ObjectIdentifier(painter)] = _PairedLines(painter: painter, shifts: shifts, saving: -acc)
                    }
                }
            }
        }
        // (A line of Latin letters alone in a paragraph on a line grid at a multiple: Word's box is the multiple of the
        // pitch it fits in, 27 pt for 14 pt Times in an 18 pt grid at 1.5 lines, where the line holding any East Asian
        // letter is the strut's two pitches (36). The text stays centred in its box, as in the strut's. Lab head2line
        // (Word for Windows, xb jpn 6fca0f's heading): the Latin-only second line is 27.00 at 14 and 11 pt, bold or not,
        // with the baseline 18.60 / 17.52 down it; with two kana added it is 36.02.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, document.usesEastAsianLayout, p.cell == nil, !style.rightToLeft, _columns <= 1, inline.isEmpty,
           style.lineSpacing > 1.001, style.lineHeightPoints == nil, !_offGrid(i, document), let pitch = _grid(i, document).pitch,
           let strut = painter.strutStyle, strut.forceStrutHeight == true, let strutSize = strut.fontSize,
           keepClear == nil, besideLineIndents.isEmpty, Self._paired(painter) == nil {
            let bottoms = Self._rawLineBottoms(painter)
            let units = Array(p.text.utf16)
            let pitchPx = _px(pitch)
            var ranges: [(Int, Int)] = []
            var at = 0
            while at < units.count, ranges.count < 200 {
                let r = painter.getLineBoundary(TextPosition(offset: at))
                guard r.end > at else { break }
                ranges.append((at, r.end)); at = r.end
            }
            if ranges.count > 1, ranges.count == bottoms.count, at == units.count, strutSize * 1.15 <= pitchPx {
                let target = style.lineSpacing * pitchPx
                var shrink = [Double](repeating: 0, count: bottoms.count)
                for line in 1 ..< bottoms.count {
                    let text = String(decoding: units[ranges[line].0 ..< ranges[line].1], as: UTF16.self)
                    let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic || ($0.value >= 0x30 && $0.value <= 0x39) }
                    guard !letters.isEmpty, !text.unicodeScalars.contains(where: { $0.value >= 0x2E80 && $0.value != 0x3000 }) else { continue }
                    let advance = bottoms[line] - bottoms[line - 1]
                    if advance > target + 0.01 { shrink[line] = advance - target }
                }
                if shrink.contains(where: { $0 > 0 }) {
                    RuleTrace.hit("word-a-latin-only-line-on-a-grid-at-a-multiple-is-the-multiple-of-its-pitches")
                    var shifts = [Double](repeating: 0, count: bottoms.count)
                    var acc = 0.0
                    for k in 0 ..< bottoms.count {
                        shifts[k] = -acc - shrink[k] / 2
                        acc += shrink[k]
                    }
                    Self._pairedLines[ObjectIdentifier(painter)] = _PairedLines(painter: painter, shifts: shifts, saving: acc)
                }
            }
        }
        // (A line with an inline picture or object in a paragraph spaced over single, in Word for Windows: the line is the tallest
        // thing above the baseline (the text's ascent or the object's top) plus the deepest below it (the text's descent or the
        // object's foot), plus the multiple's extra, (multiple - 1) times the TEXT's single line, all of it below. Lab `lowered`
        // (Word print, 26 variants of position -12 to +6 half-points, heights 9 to 30, Times and Arial 8 to 14, lines 240 to 360,
        // objects and drawings alike): pitches 19.9 / 21.2 / 22.3 / 25.3 for an 18pt object 6 down to 3 up in 11pt Times at 276,
        // 18.2 for a 9pt one, 24.3 at 360, 18.0 at 240; to 0.1pt. Not tied to the object being lowered.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, _columns <= 1,
           style.lineHeightPoints == nil, case let multiple = style.lineSpacing - theme.lineSpacingReduction, multiple > 0.999,
           // (at SINGLE spacing only a raised or lowered picture or object takes the rule: a plain one at position 0 keeps the ordinary line)
           multiple > 1.001 || inline.contains(where: { item in
               guard let img = item.image else { return false }
               let pos = p.runs.first(where: { $0.style.inlineImage == img.id }).flatMap { $0.style.raised } ?? Self._runPosition(img.sourceRunPropertiesXML) ?? 0
               return abs(pos) > 0.01
           }),
           besideLineIndents.isEmpty, keepClear == nil, Self._paired(painter) == nil,
           p.text.contains(where: { !$0.isWhitespace && $0 != "\u{FFFC}" }),
           let boxes = painter.inlinePlaceholderBoxes, boxes.count == inline.count, !boxes.isEmpty,
           let root = painter.text as? TextSpan {
            func firstTextStyle(_ span: TextSpan, _ inherited: Flutter.TextStyle) -> Flutter.TextStyle? {
                let own = inherited.merge(span.style)
                if let tx = span.text, tx.contains(where: { !$0.isWhitespace && $0 != "\u{FFFC}" }) { return own }
                for c in span.children ?? [] {
                    if let t = c as? TextSpan, let found = firstTextStyle(t, own) { return found }
                }
                return nil
            }
            let textStyle = firstTextStyle(root, Flutter.TextStyle())
            let bottoms = Self._rawLineBottoms(painter)
            let metrics = painter.computeLineMetrics()
            if let textStyle, metrics.count == bottoms.count {
                let probe = TextPainter(text: TextSpan(text: "x", style: textStyle), textDirection: .ltr)
                probe.layout(minWidth: 0, maxWidth: 10000)
                let own = probe.computeLineMetrics().first
                probe.dispose()
                if let own, own.height > 0.5 {
                    // (a probe whose line is under half its font size measured nothing, as 11pt Malgun drawn at 220 units, a line of 2.0, in Korean dx2 1f6d638c: its single then comes from the paragraph's own text line, in painter units, or the whole descent went off a picture's line.)
                    // (the probe carries the paragraph's own multiple in its style: undo it)
                    let probeFailed = own.height < (textStyle.fontSize ?? 0) * 0.5
                    let single = probeFailed ? (_tallestTextLine(i, document) ?? _markLineHeight(i, document) / multiple) : own.height / multiple
                    // (the text's own depth under the baseline at SINGLE spacing: Word's own split of the face's line where it is known
                    // (Tahoma 1.0005 over 1.2070 em), else what the engine draws; the multiple's extra the engine shares above and below is not part of it)
                    var desc = own.descent / multiple
                    // (the label reads like "(unknown).merge(((Tahoma).copyWith).copyWith)": the face is the name inside the innermost brackets)
                    let faceName = textStyle.debugLabel.flatMap { label -> String? in
                        label.split(separator: "(").compactMap { part -> String? in
                            guard let end = part.firstIndex(of: ")") else { return nil }
                            let n = String(part[part.startIndex ..< end])
                            return n.isEmpty || n == "unknown" ? nil : n
                        }.last
                    }
                    if let name = faceName, let share = theme.winDescent?(name) {
                        // (A face's own depth under the baseline in Word is its win descent (Calibri 550/2048 em: 2.96 pt at 11, where the engine's flat
                        // probe draws 2.29), read from the face's tables. 6f0b70eb p2: the step into a line holding a 13.5 pt picture, 3.42 = 2.96 + the multiple's 0.46.)
                        // (the face's win descent's share of its win line, times the line the engine drew)
                        desc = single * share
                    } else if let name = faceName, let face = theme.faceResolver?(name, false), let nh = face.naturalHeight, nh > 0.5,
                       let bl = face.baseline, bl > 0, bl < nh {
                        desc = single * (1 - bl / nh)
                    } else {
                        let flat = TextPainter(text: TextSpan(text: "x", style: textStyle.copyWith(height: (textStyle.height ?? multiple) / multiple)), textDirection: .ltr)
                        flat.layout(minWidth: 0, maxWidth: 10000)
                        desc = flat.computeLineMetrics().first?.descent ?? desc
                        flat.dispose()
                    }
                    var above = [Double](repeating: -1, count: bottoms.count), below = above
                    var shiftsOwn = [Double](repeating: 0, count: bottoms.count)
                    var wrappedPlain = Set<Int>()
                    for (k, box) in boxes.enumerated() {
                        guard inline[k].image != nil, inline[k].image?.float == nil, inline[k].image?.textBox == nil,
                              inline[k].image?.name != "m:oMath", let img = inline[k].image else { continue }
                        // (A plain picture at position 0 takes part too: it raises only its own line, and every line of the
                        // paragraph takes the multiple's extra below.)
                        let pos = p.runs.first(where: { $0.style.inlineImage == img.id }).flatMap { $0.style.raised } ?? Self._runPosition(img.sourceRunPropertiesXML) ?? 0
                        let r = box.toRect()
                        let mid = r.top + r.height / 2
                        guard let line = bottoms.firstIndex(where: { mid < $0 }) else { continue }
                        if abs(pos) <= 0.01 {
                            // (A plain chart that stands ALONE on a later line, after a line of text: the chart wrapped. (Not a picture: 8f697d90's screenshots at 1.08 do not take it.) Word puts
                            // the multiple's extra under the text line and under the picture line alike; lab probe1-4 on dx2 f15415f0,
                            // heading 11pt Verdana at 360 then a 272pt-wide chart: heading 438.9, chart line 748.8 from 735.0 single.)
                            if line > 0, img.sourceXML?.containsSubstring("drawingml/2006/chart") == true, metrics[line].width <= r.width + 1, r.height > 1.5 * bottoms[0], inline.count == 1 {
                                wrappedPlain.insert(line)
                            }
                        }
                        // (a placeholder the first-line rule enlarged for the text's room under the baseline: its foot is the picture's own)
                        let grown = _pageFill[img.id].map { max(0, r.height - $0) } ?? 0
                        above[line] = max(above[line], metrics[line].baseline - r.top - (multiple > 1.001 ? 0 : grown))
                        below[line] = max(below[line], r.bottom - grown - metrics[line].baseline)
                    }
                    // (Only while the pictures stay within the text's own line: lab afbaab-multiple has 12.75pt pictures in 11pt
                    // Tahoma. A taller picture is not in the lab, and a8f4dfcd's 20pt icons in 1.5 Tahoma 12 do not fit the formula.)
                    let tallPic = zip(boxes, inline).contains { box, il in
                        let grown = il.image.flatMap { _pageFill[$0.id] }.map { max(0, box.toRect().height - $0) } ?? 0
                        return box.toRect().height - grown > single * 1.05
                    }
                    if wrappedPlain.isEmpty, !tallPic, above.contains(where: { $0 >= 0 }) {
                        // (Word's print, lab afbaab-multiple, 27 lines to 0.1 pt: EVERY line of the paragraph stands max(text ascent, picture top)
                        // above its baseline, and below it go the text's descent plus ALL of the multiple's extra, so a line without
                        // an object takes the same formula.)
                        for k in 0 ..< bottoms.count where above[k] < 0 { above[k] = 0; below[k] = 0 }
                    }
                    var extra = [Double](repeating: 0, count: bottoms.count)
                    for line in 0 ..< bottoms.count where above[line] >= 0 {
                        let before = line == 0 ? 0 : bottoms[line - 1], advance = bottoms[line] - before
                        // (A picture TALLER than the text line: the engine shares the multiple's extra between above and below the text of
                        // every line, and Word puts all of it below; the two differ by the same amount on the next text line, so the pitch into
                        // the next line matches only if this line keeps the engine's own share, desc x multiple (a8f4dfcd's 20pt icons in
                        // 1.5 Tahoma 12: Word 22.68 out of the line, 23.52 into it).)
                        let target = tallPic ? max(single - desc, above[line]) + max(desc, below[line]) * multiple
                            : max(single - desc, above[line]) + max(desc, below[line]) + (multiple - 1) * single
                        extra[line] = target - advance
                        // (Where the growth sits: the object's top pushes THIS line's own baseline down, its foot adds below it. Word's
                        // print of 1d944f7b: pitches 24.0 into the object's line and 23.1 out of it, 2.6 + 6.9 + 14.4 and 5 + 6.9 + 11.2.)
                        let want = max(single - desc, above[line])
                        shiftsOwn[line] = min(want - (metrics[line].baseline - before), max(0, extra[line]))
                        if wrappedPlain.contains(line) {
                            // (painter units here are not the probe's: take the text line's own single height from line 0)
                            extra[line] = (multiple - 1) * bottoms[0] / multiple
                            shiftsOwn[line] = 0
                        }
                    }
                    if !wrappedPlain.isEmpty {
                        // (the text lines before the picture: the multiple's extra goes under them, not above)
                        RuleTrace.hit("word-a-wrapped-plain-picture-line-takes-the-multiples-extra-under-it-and-the-text-above-it")
                        for k in 0 ..< bottoms.count where above[k] < 0 {
                            let before = k == 0 ? 0 : bottoms[k - 1]
                            shiftsOwn[k] = -(metrics[k].baseline - before) * (multiple - 1) / multiple
                        }
                    }
                    if extra.contains(where: { abs($0) > 0.05 }) || shiftsOwn.contains(where: { abs($0) > 0.05 }) || !wrappedPlain.isEmpty {
                        RuleTrace.hit("word-a-line-with-an-object-is-its-tallest-and-deepest-plus-the-multiples-extra-below")
                        var shifts = [Double](repeating: 0, count: bottoms.count)
                        var acc = 0.0
                        for k in 0 ..< bottoms.count {
                            shifts[k] = acc + shiftsOwn[k]
                            acc += extra[k]
                        }
                        Self._pairedLines[ObjectIdentifier(painter)] = _PairedLines(painter: painter, shifts: shifts, saving: -acc, objects: true)
                    }
                }
            }
        }
        // (A line that holds text its run raises or lowers (`w:position`), in a paragraph of single spacing: Word makes the line as
        // tall as the text's top plus the raise, and as deep as its foot plus the lowering. Lab CP3 (xb docx-8f1703b9, 11pt Calibri,
        // "raised" at 6pt, "lowered" at -6pt): pitches 19.44 into the raised line (13.44 + 6, above its baseline), 13.44 out of it,
        // 19.44 out of the lowered line (6 below it). A shorter run's own ascent and descent scale with its size.)
        // (A top-aligned paragraph's lowering may stand in its style (`w:position` in the paragraph style's run properties).)
        let lowTop = style.eastAsian["w:textAlignment"] == "top"
        let lowNamed = lowTop ? _named(p, document)?.char.raised : nil
        func raisedOf(_ r: Run) -> Double { r.style.raised ?? lowNamed ?? 0 }
        if theme.wordRules, RichTextTheme.wordWindowsPages, !style.rightToLeft,
           style.lineHeightPoints == nil,
           style.lineSpacing - theme.lineSpacingReduction <= 1.001 || style.eastAsian["w:textAlignment"] == "top",
           besideLineIndents.isEmpty, keepClear == nil, Self._paired(painter) == nil,
           p.runs.contains(where: { abs(raisedOf($0)) > 0.01 && $0.style.script == .normal }),
           // (A numbered line's raise (up to 2pt, lab pitch2) is taken off the number's rise instead: see the number span.)
           !(p.style.list != nil && !lowTop && p.runs.allSatisfy({ abs(raisedOf($0)) <= 2.01 })) {
            let metrics = painter.computeLineMetrics()
            let bottoms = Self._rawLineBottoms(painter)
            let units = p.text.utf16.count
            let starts = _lineStarts(painter, _map(i), count: units)
            if metrics.count == bottoms.count, starts.count == metrics.count {
                var above = [Double](repeating: 0, count: metrics.count), below = above
                var tallest = [Double](repeating: 0, count: metrics.count)
                var unraised = [Bool](repeating: false, count: metrics.count)
                var at = 0
                let text = Array(p.text.utf16)
                for run in p.runs where run.length > 0 {
                    defer { at += run.length }
                    guard at < units else { break }
                    let end = min(units, at + run.length)
                    guard text[at ..< end].contains(where: { $0 > 0x20 }) else { continue }
                    let line = max(0, (starts.lastIndex(where: { $0 <= at }) ?? 0))
                    tallest[line] = max(tallest[line], run.style.fontSize ?? 0)
                    if abs(raisedOf(run)) < 0.01 || raisedOf(run) < 0 { unraised[line] = true }
                }
                // Lines whose every text run is lowered by one same amount, in a top-aligned paragraph: that amount (px), else 0.
                var topLine = [Double](repeating: 0, count: metrics.count)
                var glyphAdj = [Double](repeating: 0, count: metrics.count)
                if style.eastAsian["w:textAlignment"] == "top" {
                    var seen = [Double?](repeating: nil, count: metrics.count), mixed = [Bool](repeating: false, count: metrics.count)
                    var q = 0
                    for run in p.runs where run.length > 0 {
                        defer { q += run.length }
                        guard q < units else { break }
                        let e = min(units, q + run.length)
                        guard text[q ..< e].contains(where: { $0 > 0x20 }) else { continue }
                        let line = max(0, (starts.lastIndex(where: { $0 <= q }) ?? 0))
                        let r = raisedOf(run)
                        if let s0 = seen[line] { if abs(s0 - r) > 0.01 { mixed[line] = true } } else { seen[line] = r }
                    }
                    for k in 0 ..< metrics.count where !mixed[k] { if let r = seen[k], r < -0.01 { topLine[k] = -r * _px(1) } }
                }
                at = 0
                for run in p.runs where run.length > 0 {
                    defer { at += run.length }
                    guard at < units else { break }
                    let end = min(units, at + run.length)
                    guard text[at ..< end].contains(where: { $0 > 0x20 }) else { continue }
                    // (Only Latin text is measured: CJK, Thai and symbol-font runs raised in the corpus (xd, xb) are
                    // set on the lines Word sets them on without the growth.)
                    let lineOfRun = max(0, (starts.lastIndex(where: { $0 <= at }) ?? 0))
                    guard topLine[lineOfRun] > 0 || text[at ..< end].allSatisfy({ $0 <= 0x24F || (0x2000 ... 0x206F).contains($0) }) else { continue }
                    let pos = raisedOf(run) * _px(1)
                    guard abs(raisedOf(run)) > 0.01, run.style.script == .normal else { continue }
                    let line = max(0, (starts.lastIndex(where: { $0 <= at }) ?? 0))
                    let ratio = tallest[line] > 0 ? (run.style.fontSize ?? tallest[line]) / tallest[line] : 1
                    let m = metrics[line]
                    // (Above single spacing only the uniformly lowered top-aligned lines are measured: the raise/lower growth is verified at single.)
                    if topLine[line] == 0, style.lineSpacing - theme.lineSpacingReduction > 1.001 { continue }
                    if !p.inlineImages.isEmpty {
                        // (A line with an inline picture or object stands on the picture's foot; raised text grows it only where its top, the
                        // raise over its own ascent, passes the line's. Word's print, sa1 a7044bb8: a 46.5 pt object beside 26 pt Old English
                        // Text MT raised 23 pt stands 49.04 under the header's top, 23 + the face's win ascent 26.08, where the engine's
                        // line stood 47.75.)
                        guard pos > 0, topLine[line] == 0 else { continue }
                        var single = style; single.lineSpacing = 1
                        if let b = theme.baseline(for: run.style, in: single, named: _named(p, document), eastAsian: false, gridPitch: nil, centresInLine: false),
                           pos + b * _px(1) > m.ascent + 0.05 {
                            RuleTrace.hit("word-raised-text-beside-an-inline-picture-grows-the-line-to-its-top")
                            above[line] = max(above[line], pos + b * _px(1) - m.ascent)
                        }
                        continue
                    }
                    if topLine[line] > 0 {
                        // (Top-aligned text lowered by L: the line is max(single, its ink box + L) tall, the lowering first eating the face's
                        // spare line gap; the glyphs stand that much below where the unlowered line sets them. Lab pos14, amd-opus.)
                        let multiple = max(1, style.lineSpacing - theme.lineSpacingReduction)
                        let single = m.height / multiple
                        let family = run.style.fontFamily ?? _named(p, document)?.char.fontFamily ?? theme.fontFamily
                        let em = max(1, run.style.fontSize ?? _named(p, document)?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize) * _px(1)
                        let box = theme.winLineBox?(family).map { $0 * em } ?? (m.ascent + m.descent) * ratio / multiple
                        let grown = max(0, box - pos - single)
                        if grown > above[line] { RuleTrace.hit("word-top-aligned-lowered-text-line-is-ink-box-plus-lowering"); above[line] = grown }
                        // (The glyphs keep the lowering the text style gives them; they stand `grown` below the unlowered line, so take it back.)
                        glyphAdj[line] = -topLine[line]
                        continue
                    }
                    if pos > 0, !unraised[line] {
                        // (Lab shadow3, Word's print, Calibri: a line whose every run is raised stands on its baseline alone, so the raise grows it
                        // only by what passes the descent below the baseline: 12 pt raised 6 pt grows 2.76 (6 - 0.2686 x 12), raised 1 or 3 pt
                        // nothing, and at 24 and 55 pt raised 6 pt nothing. A shadow's reach below the run counts with the descent.)
                        RuleTrace.hit("word-a-line-of-raised-runs-only-grows-by-the-raise-past-its-descent")
                        // (Without a shadow the engine's own line already stands the raised run on its baseline: nothing to add.)
                        guard run.style.shadow != nil else { continue }
                        var reachBelow = 0.0, reachAll = 0.0
                        if let sh = run.style.shadow, !sh.glow, sh.blur > 0 {
                            let r = Self._shadowReach(sh, pt: run.style.fontSize ?? 0)
                            reachBelow = r.below * _px(1); reachAll = (r.above + r.below) * _px(1)
                        }
                        // (The line's descent holds the shadow's whole reach under the run; the face's own is what is left.)
                        var descFace = m.descent * ratio - reachAll
                        do {
                            var single = style; single.lineSpacing = 1
                            let fam = run.style.fontFamily ?? _named(p, document)?.char.fontFamily ?? theme.fontFamily
                            let sz = max(1, run.style.fontSize ?? _named(p, document)?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize)
                            if let boxEm = theme.winLineBox?(fam),
                               let b = theme.baseline(for: run.style, in: single, named: _named(p, document), eastAsian: false, gridPitch: nil, centresInLine: false), b / sz < boxEm { descFace = (boxEm - b / sz) * sz * _px(1) }
                        }
                        above[line] = max(above[line], pos - descFace - reachBelow)
                        continue
                    }
                    above[line] = max(above[line], m.ascent * ratio + pos - m.ascent)
                    below[line] = max(below[line], m.descent * ratio - pos - m.descent)
                }
                if above.contains(where: { $0 > 0.05 }) || below.contains(where: { $0 > 0.05 }) {
                    RuleTrace.hit("word-a-line-with-a-raised-or-lowered-run-grows-by-the-raise-above-and-the-lowering-below")
                    var shifts = [Double](repeating: 0, count: metrics.count)
                    var acc = 0.0
                    for k in 0 ..< metrics.count {
                        shifts[k] = acc + max(0, above[k]) + glyphAdj[k]
                        acc += max(0, above[k]) + max(0, below[k])
                    }
                    Self._pairedLines[ObjectIdentifier(painter)] = _PairedLines(painter: painter, shifts: shifts, saving: -acc)
                }
            }
        }
        if (besideLeftRoom != nil && !besideLineIndents.isEmpty) || keepClear != nil {
            Self._registerPairs(painter, besideLeftRoom != nil ? besideLineIndents : [], push: keepClear)
        }
        _painters[i] = painter
        _textLeft[i] = left
        _textWidth[i] = textWidth
        // An object that floats over the paragraph's head with text
        // wrapping round it, and leaves the first line no room on either
        // side of it — the line's indent is taken off each — sets the
        // text down under it, as Word does: a box across the column
        // with the title of the page in it, anchored in the paragraph
        // of the line below. (Lines set beside a narrower one are not
        // built: the text then runs over it, as before.)
        var push = 0.0
        // Whether the paragraph's first line ends above a float that many
        // pixels down from its top: its space before as pagination keeps it
        // where the paragraph opens a section on a new page (less the space
        // after the paragraph before), then the line.
        let firstLine: () -> (top: Double, line: Double)? = { [self] in
            guard theme.wordRules, let first = painter.computeLineMetrics().first else { return nil }
            var top = before
            if i > 0, let xml = document.paragraphs[i - 1].style.sectionXML, !xml.containsSubstring("\"continuous\""), _cells[i - 1] == nil {
                top = max(0, before - _spacing(i - 1, document).after)
            }
            // (An empty line's height is its exact one, else its size's.)
            var line = first.height
            if let exact = style.lineHeightPoints, !style.lineHeightIsMinimum, exact > 0 { line = _px(exact) }
            else if line < 1 { line = _px(p.runs.first?.style.fontSize ?? theme.fontSize) }
            return (top, line)
        }
        let lineEndsAbove: (Double) -> Bool = { down in
            guard let first = firstLine() else { return false }
            return first.top + first.line <= down + 0.01
        }
        // How far down a line its float leaves no room beside goes: Word
        // steps it from where it first stood by the line and its space
        // before at a time, as if each try were a fresh line paying its
        // before again, and takes the first step clear of the float's
        // foot (lab t3d, Word for Windows, zh-d62da4dd's item 21: an exact
        // 27pt line under 9pt before, first at 9, set at 261 under a chart
        // whose foot is 244.8 down — at 225, 261, 297 as the foot moves
        // 208.8, 226.8, 262.8; with 18pt before, 18 + 45k; zh-27a874b7's
        // title steps the same way from 36, by 31.84). The push is what is
        // added to the space before.
        // (A line of an exact height, as the lab's: a single line goes to
        // the foot — zh-4adfcce2's title, the box's anchor, stands just
        // under the box in the Mac's print, where three steps of its
        // line sent it 19pt lower; zh-d62da4dd's exact anchor steps in
        // both prints.)
        // (And, in Word for Windows, a line on the line grid: by the grid
        // line less the grid's half of the room under its text, until its
        // text's top is clear of the foot — lab tph (windows-1,
        // zh-37b6536f's p2): the empty anchor of a row of photos, 16pt
        // 仿宋_GB2312 on a 15.6 grid, steps 26.0 = (31.2 + 20.8) / 2, its
        // place holding while the foot moves 239.3 to 257.3; ours set it
        // at the foot, and the row under it stood 5.5pt high.)
        let pushUnder: (Double) -> Double = { [self] foot in
            guard let first = firstLine(), first.line + before > 1 else { return foot }
            if let exact = style.lineHeightPoints, exact > 0, !style.lineHeightIsMinimum {
                let step = first.line + before
                let k = max(0, ((foot - first.top) / step - 0.001).rounded(.up))
                return max(0, first.top + k * step - before)
            }
            // (A line of spaces at a multiple above one steps by the single line, not the multiple; labs hinhdr2 (empty lines) did not fit this, so spaces only: hin b05873's
            // header, 18 spaces of Calibri 11 at 1.15 under a picture 72pt down, is set 6 steps of 13.43 from its
            // top, 80.6, in Word's print, and in labs hinhdr2 A, D, E, F, the picture's foot moving 5pt up and down;
            // ours set it at the foot.)
            if RichTextTheme.wordWindowsPages, style.lineHeightPoints == nil, style.lineSpacing > 1.001 || (headerTopOnPage != nil && !p.text.unicodeScalars.contains(where: { $0 == " " })), style.besideFloat == false,
               p.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC || $0 == " " }),
               case let step = (!p.text.unicodeScalars.contains(where: { $0 == " " }) ? _markLineHeight(i, document, single: true) : first.line / style.lineSpacing) + before, step > 1 {
                let k = max(0, ((foot - first.top) / step - 0.001).rounded(.up))
                RuleTrace.hit("word-line-of-spaces-steps-clear-of-its-float-by-the-single-line")
                return max(0, first.top + k * step - before)
            }
            guard RichTextTheme.wordWindowsPages, style.lineHeightPoints == nil, case let half = _firstLineGridHalf(i, document), half > 0.01,
                  case let step = first.line - half + before, step > 1 else { return foot }
            let k = max(0, ((foot - half - first.top) / step - 0.001).rounded(.up))
            return max(0, first.top + k * step - before)
        }
        // (A header's empty line steps down from the header's top by the single line, and stops at the first step where the pictures
        // wrapping around it, page-relative ones too, leave a gap as wide as its font size: dx2 cy 096a80c1's header, three tight pictures,
        // Word's line at step 3 where the right one clears and 125pt opens beside the middle one, not under the lowest foot.)
        var headerStepped = false
        if theme.wordRules, p.cell == nil, RichTextTheme.wordWindowsPages, let hTop = headerTopOnPage, style.lineHeightPoints == nil,
           p.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC || $0 == " " }), _firstLineGridHalf(i, document) <= 0.01, let first = firstLine() {
            let column = _flowWidth(i)
            let lo = max(0, lead) + (left - (frameLeft ?? 0))
            let hi = column - right
            let em0 = _px(p.runs.first?.style.fontSize ?? theme.fontSize)
            var boxes: [(Double, Double, Double, Double)] = []
            for image in p.inlineImages.inOrder {
                guard let float = image.float, float.wraps, float.verticalAlign == nil, ["paragraph", "line", "page"].contains(float.verticalFrom) else { continue }
                let w = min(_px(image.width), column)
                let x: Double
                switch float.horizontalAlign {
                case "center": x = (column - w) / 2
                case "right", "outside": x = column - w - (theme.wordRules && float.horizontalAlign == "right" ? _px(float.effectRight) : 0)
                case "left", "inside": x = 0
                default: x = _px(float.x) - (float.horizontalFrom == "page" ? _px(frameMargins.left) : 0)
                }
                let y = _px(float.y) - (float.verticalFrom == "page" ? hTop : 0)
                boxes.append((x - _px(float.distanceLeft ?? 9), x + w + _px(float.distanceRight ?? 9),
                              y - _px(float.distanceTop), y + _px(image.height + float.effectBottom + float.distanceBottom)))
            }
            if !boxes.isEmpty {
                let step = _markLineHeight(i, document, single: true) + before
                if step > 1 {
                    let lineH = step - before
                    var k = 0.0
                    while k < 60 {
                        let t = first.top + k * step
                        let hit = boxes.filter { $0.2 < t + lineH - 0.01 && $0.3 > t + 0.01 }.sorted { $0.0 < $1.0 }
                        var widest = 0.0, edge = lo
                        for b in hit { widest = max(widest, b.0 - edge); edge = max(edge, b.1) }
                        widest = max(widest, hi - edge)
                        if widest >= em0 { break }
                        k += 1
                    }
                    if k > 0 { RuleTrace.hit("word-header-empty-line-steps-to-the-first-gap-beside-its-pictures") }
                    push = max(push, max(0, first.top + k * step - before))
                    headerStepped = true
                }
            }
        }
        if theme.wordRules, p.cell == nil, !headerStepped {
            let column = _flowWidth(i)
            let firstLine = max(0, lead) + (left - (frameLeft ?? 0))
            // (Together, too: two photos side by side that fill the
            // column between them set an empty anchor's line under both,
            // where either alone leaves room — zh-37b6536f's first row.)
            var spans: [(Double, Double, Double)] = []
            let em0 = _px(p.runs.first?.style.fontSize ?? theme.fontSize)
            for image in p.inlineImages.inOrder {
                guard let float = image.float, float.wraps, float.verticalAlign == nil, ["paragraph", "line"].contains(float.verticalFrom),
                      float.horizontalFrom != "page", float.horizontalAlign == nil else { continue }
                // (Only a float whose band the line reaches: one that starts below the line's foot leaves it the whole width above.
                // dx2 2f747ec3's three text boxes, the nearest 29.7pt down under a 19.7pt line: Word keeps the line at the top and
                // the page's first box under it; ours put it under all three, 624pt down, and the paragraph went to the next page.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, lineEndsAbove(_px(float.y - float.distanceTop)) { continue }
                let w = _px(image.width)
                spans.append((_px(float.x) - _px(9), _px(float.x) + w + _px(9), _px(float.y) + _bodyBoxHeight(image, document)))
            }
            if spans.count > 1 {
                let sorted = spans.sorted { $0.0 < $1.0 }
                var widest = 0.0, edge = firstLine
                for s in sorted { widest = max(widest, s.0 - edge); edge = max(edge, s.1) }
                widest = max(widest, column - max(0, lead) - right - edge)
                if widest < em0 { push = max(push, pushUnder(sorted.map(\.2).max() ?? 0)) }
            }
            for image in p.inlineImages.inOrder {
                guard let float = image.float, float.wraps, float.verticalAlign == nil, ["paragraph", "line"].contains(float.verticalFrom),
                      float.horizontalFrom != "page" else { continue }
                let w = min(_px(image.width), column)
                let x: Double
                switch float.horizontalAlign {
                case "center": x = (column - w) / 2
                case "right", "outside": x = column - w
                case "left", "inside": x = 0
                default: x = _px(float.x)
                }
                // (An empty paragraph's line asks no width: any room beside
                // the float holds it. zh-d62da4dd's empty anchors of two
                // charts wrapped tight: the first leaves none on either side
                // and its line goes under it in Word's print; the second
                // leaves 1.95pt on its right, and its line stays — ours sent
                // both under, and page 4 ran onto a fifth.)
                // (Empty but for its floating objects' places.)
                let bare = p.text.unicodeScalars.allSatisfy { $0.value == 0xFFFC || $0 == " " }
                let gap = _px(9), em = theme.wordRules && bare ? 0.0 : _px(p.runs.first?.style.fontSize ?? theme.fontSize)
                let leftRoom = x - gap - firstLine, rightRoom = column - (x + w) - gap - (em > 0 ? max(0, lead) : 0) - right
                // (Not where the line ends above it: zh-27a874b7's page 3
                // opens a section with the same empty anchor as zh-d62da4dd's,
                // its 27pt exact line, its chart 27.3pt down — but there the
                // page's top takes its 9pt before away, the line ends at 27,
                // and Word's print keeps it, and the box that goes with it,
                // over the chart (lab ss); in zh-d62da4dd, mid-page, the
                // line from 9 to 36 goes under.)
                // (Under its drawn effects too: lab t8e, zh-8e8d4c40's title
                // under its 【附件五】 box, b 11430 EMU, 0.9pt below the
                // frame's foot in Word for Windows.)
                if em > 0 ? (leftRoom < em && rightRoom < em) : (leftRoom <= 0 && rightRoom <= 0),
                   !lineEndsAbove(_px(float.y)) { push = max(push, pushUnder(_px(float.y) + _px(image.height + float.effectBottom + float.distanceBottom))) }
            }
        }
        // (In a table cell too, across the cell's text — lab `wc` on Word
        // for Windows: zh-e4ef4c4d's 184pt photo, anchored 15.4pt down in a
        // cell 201pt across inside its margins, sets its paragraph's text
        // under it, where ours ran the text over it. A line of an exact
        // height goes down by whole lines from the paragraph's top — 24pt
        // lines to 168pt under a photo that ends 153.75 down, 144 under
        // one ending 135.4 — and one of auto spacing to just under it.)
        else if theme.wordRules, let cell = p.cell, cell.textDirection == .horizontal {
            let bare = p.text.unicodeScalars.allSatisfy { $0.value == 0xFFFC || $0 == " " }
            let gap = _px(9), em = bare ? 0.0 : _px(p.runs.first?.style.fontSize ?? theme.fontSize)
            for image in p.inlineImages.inOrder {
                guard let float = image.float, float.wraps, !float.takesRoom, float.verticalAlign == nil,
                      float.verticalFrom == "paragraph", float.horizontalFrom != "page" else { continue }
                let w = min(_px(image.width), textWidth)
                let x: Double
                switch float.horizontalAlign {
                case "center": x = (textWidth - w) / 2
                case "right", "outside": x = textWidth - w
                case "left", "inside": x = 0
                default: x = _px(float.x)
                }
                let leftRoom = x - gap - max(0, lead), rightRoom = textWidth - (x + w) - gap
                guard em > 0 ? (leftRoom < em && rightRoom < em) : (leftRoom <= 0 && rightRoom <= 0) else { continue }
                var under = _px(float.y) + _bodyBoxHeight(image, document)
                if let exact = style.lineHeightPoints, !style.lineHeightIsMinimum, exact > 0, under > 0 {
                    under = (under / _px(exact) - 0.001).rounded(.up) * _px(exact)
                }
                push = max(push, under)
            }
        }
        // (A paragraph of nothing but an object that bands the page from
        // it, placed some way down, sets its own line under the object:
        // lab `rul` (Word for Windows, zh-3da9d7f2's package) — its red
        // rule, a level line wrapped top and bottom 21.9pt down an empty
        // exact 27pt paragraph with a 1.25pt bottom effect, puts that
        // paragraph's line 23.15 lower, the offset, the height and the
        // effect, at every offset from 3 to 27pt and under "at least"
        // too. At no offset, or with no height and no effect, nothing:
        // zh-f47b8a74's first rule is drawn over its line. Nor where the
        // line ends above the object: zh-7773163d's cover picture, 367pt
        // wrapped top and bottom 16.65pt down an empty paragraph whose
        // 7.5pt mark's line ends near 11, has that line over it in Word's
        // print and the next paragraph under it.)
        // (A chart does it with text in its paragraph too: lo-ccd9da4b's, a hair under its
        // line's top, has "xxxx" under it in Word's print.)
        if theme.wordRules, p.cell == nil, RichTextTheme.wordWindowsPages || p.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC || $0 == " " }) {
            let bareText = p.text.unicodeScalars.allSatisfy { $0.value == 0xFFFC || $0 == " " }
            for image in (p.image.map { [$0] } ?? []) + p.inlineImages.inOrder {
                guard bareText || image.sourceXML?.containsSubstring("drawingml/2006/chart") == true else { continue }
                // (A hair above the line, -0.9pt as in lo-eb12e7d4's 137pt picture, in an empty
                // paragraph: Word sets the line under it all the same — its p12 has the picture
                // where the paragraph stood and the next paragraph at its foot, not over it.)
                // (A picture banded top and bottom, 30pt above the empty first paragraph that holds it: Word stands it
                // at the margin and the line goes under it — 3cce370f's picture 72 to 134.2 where ours stood at 42,
                // every line after it 42.5pt high. One document's evidence, so only the document's first paragraph.)
                let atTop = _atPageTopNegativeOffset(i, image)
                guard let f = image.float, f.bandsPage, f.verticalFrom == "paragraph", f.verticalAlign == nil,
                      f.y > 0 || atTop || (RichTextTheme.wordWindowsPages && bareText && f.y < -0.3 && f.y > -2),
                      image.height + f.effectBottom > 0, before + max(painter.height, _markLineHeight(i, document)) >= _px(f.y) - 0.01 else { continue }
                // (… and one more line than the picture's height: Word's p12 has two lines under it before the next paragraph.)
                if atTop {
                    RuleTrace.hit("word-top-and-bottom-picture-above-the-margin-stands-at-it-and-the-line-goes-under")
                    push = max(push, _px(image.height + f.effectBottom + f.distanceBottom))
                    continue
                }
                // (A picture whose foot lies inside the paragraph's own space before: the line stands where that space puts it and
                // is not pushed again. sa2 78bf1be7's header, a 0.75pt rule 0.9pt down an empty paragraph with 2.95pt before: the body
                // starts at 106.9 in Word's print, ours 1.6pt lower with the foot added to the space.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, f.y > 0, _px(f.y + image.height + f.effectBottom + f.distanceBottom) <= before + 0.01 {
                    RuleTrace.hit("word-top-and-bottom-picture-inside-the-space-before-does-not-push-the-line")
                    continue
                }
                push = max(push, _px(f.y + image.height + f.effectBottom + f.distanceBottom) + (f.y < 0 ? max(painter.height, _markLineHeight(i, document)) : 0))
            }
        }
        // (A paragraph of nothing but a square-wrapped box placed from the page that spans the text's whole width, no room at either
        // side: its own line cannot stand beside it and goes under it, as under a top-and-bottom one. xd bf53d2b7's title bar, 613 pt
        // from x -19.7 on a 612 pt page, anchored in an empty paragraph: Word's print has the next paragraph, a picture, 65 pt lower
        // than ours, which had left the picture in the box's band.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.cell == nil, p.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC || $0 == " " }) {
            let setup = _setup(ofParagraph: i)
            for image in (p.image.map { [$0] } ?? []) + p.inlineImages.inOrder {
                guard let f = image.float, f.wraps, !f.takesRoom, !f.bandsPage, f.verticalFrom == "paragraph", f.verticalAlign == nil, f.y >= 0,
                      f.horizontalFrom == "page", f.horizontalAlign == nil, image.textBox != nil, image.height > 0 else { continue }
                let left = f.x - setup.marginLeft
                let right = setup.width - setup.marginRight - (f.x + image.width)
                guard left < 12, right < 12 else { continue }
                RuleTrace.hit("word-empty-paragraph-line-goes-under-a-box-that-leaves-no-room-beside")
                push = max(push, _px(f.y + image.height + f.effectBottom + f.distanceBottom))
            }
        }
        // (A picture wrapped top and bottom that stands at the top of the paragraph holding
        // its anchor, text and all: the first line goes under it, the picture where it was.
        // Lab `anc` (Word for Windows, one column and two): 40pt at (20, 0) in p3 puts p3 at
        // the picture's foot, 40pt down, and the rest after it; 100pt, 100 down.)
        // (Offset exactly 0, the lab's one value, and a picture or drawing, not a text box: LibreOffice's
        // tdf137850's box at offset 0 stays at the margin in Word's print.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.cell == nil, !p.text.isEmpty, !style.rightToLeft, !p.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC || $0 == " " }) {
            for image in p.inlineImages.inOrder {
                guard let float = image.float, float.takesRoom || float.bandsPage, !float.wraps, float.verticalAlign == nil,
                      float.verticalFrom == "paragraph", float.y.magnitude < 0.01 || (float.y < 0 && float.y + image.height + float.effectBottom > 0), float.horizontalFrom != "page",
                      image.height > 0, float.wrapSide == nil, !image.data.isEmpty || Self.drawsObject?(image) == true else { continue }
                // (A hair of it above the paragraph, 24pt up in sa2 86737b97: Word does not lift it to the margin, it stands
                // 24pt above the paragraph and the first line is set at its foot, 36.25pt down.)
                if !lineEndsAbove(-_px(float.distanceTop)) {
                    RuleTrace.hit("word-first-line-set-under-a-top-and-bottom-picture-at-the-paragraphs-top")
                    push = max(push, pushUnder(_px(float.y + image.height + float.effectBottom + float.distanceBottom)))
                }
                break
            }
        }
        // (Under a header's box that leaves the text no room: `_headerBoxFloor`.)
        if let under = _headPushUse[i], under > push { push = under }
        // (Text beside a tight-wrapped picture anchored in an earlier paragraph, whose first line would start above the
        // picture's band: Word's print sets that line at the band's top. c88ca385, a4bf2c03: the list and the line under
        // the logo stand 4.4pt lower than ours.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, _besideListEarlier.contains(i) || _besideIndentOnTop.contains(i),
           let band = besideBand, (_besideTightTop[i] ?? band.top) > 0.01, band.top < painter.height { push = max(push, _besideTightTop[i] ?? band.top); RuleTrace.hit("word-first-line-beside-earlier-tight-float-starts-at-its-band") }
        if i < _floatPush.count { _floatPush[i] = push }
        if i < _floatTight.count { _floatTight[i] = p.inlineImages.inOrder.contains { $0.float?.wraps == true && $0.float?.wrapsTight == true } }
        _spaceBefore[i] = before + push
        var bodyHeight = painter.height + _px(segoeLift) - w2Trim
        if let pair = Self._paired(painter) { bodyHeight -= pair.saving }
        if i < _firstLineLift.count { _firstLineLift[i] = _px(segoeLift) }
        // A paragraph of nothing but floating objects stands as one of a
        // single floating picture does (25pt in zh-37b6536f, where the
        // two photos' 0-high places made a line of 0.8, and the next
        // photo stood 30pt above Word's).
        // (One floating object alone, too: zh-1a3c7aa0's footer is a
        // page number's text box in a 9pt run, its mark 14pt, and Word's
        // line is the mark's — the box, which hangs from the line's top,
        // stood 8.3pt low on every page.)
        // (So does the rest of a page-break paragraph that is nothing but
        // spaces, with or without floating objects: its line is its
        // mark's, however large the spaces —
        // lab t194 (Word for Windows, windows-1): zh-20c1d74a p15 opens
        // with the rest of a page-break paragraph, two wrapNone boxes
        // and a " " in 標楷體, and Word's line is the TNR mark's 13.8, as
        // without the boxes or with the space at 24pt; with "文" for it,
        // 標楷體's 15.6.)
        // (Only where a page break opens it, as there: a lone " "
        // paragraph of its own stands on its run's line in Word's prints —
        // zh-61aaad09's 14pt 楷体 one, zh-f0bd9ea8's.)
        let spacesOnly = theme.wordRules && p.style.pageBreakInline && p.image == nil && p.text.unicodeScalars.contains(" ")
            && p.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC || $0 == " " })
            && p.inlineImages.values.allSatisfy({ $0.float.map { !$0.takesRoom } ?? false })
        if theme.wordRules, spacesOnly ||
           p.image.map({ $0.float.map { !$0.takesRoom } ?? false }) ?? (!p.inlineImages.isEmpty && !p.text.isEmpty
               && p.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC })
               && p.inlineImages.values.allSatisfy({ $0.float.map { !$0.takesRoom } ?? false })) {
            // (As a paragraph of one floating picture is laid out — its
            // character in the objects' run, with no object in it: the
            // height Word gives such a line, 25pt where a line of text
            // is 29.)
            // (The paragraph mark's look: the objects' runs may carry none.)
            var mark = p.style.mark ?? p.runs.first?.style ?? CharStyle()
            mark.inlineImage = nil
            var empty = RichParagraph(text: "\u{FFFC}", runs: [Run(length: 1, style: mark)], style: p.style)
            empty.cell = p.cell
            let (span, held, _) = _span(for: empty, at: nil, document, textWidth: textWidth)
            let probe = TextPainter(text: span, textAlign: .left, textDirection: .ltr,
                                    strutStyle: held.contains(where: { $0.image != nil }) ? nil : _strut(span))
            probe.fractionalLineHeights = theme.wordRules
            if !held.isEmpty { probe.setPlaceholderDimensions(held.map { $0.dimensions }) }
            probe.layout(minWidth: 0, maxWidth: max(1, textWidth))
            // (Floating boxes that take no room set no height: the mark's line is the whole of it, not the larger
            // of that and the line the boxes' places made — xd 6be5dbc9's stamp box, one 11pt Times mark, Word's
            // 12.65 where ours kept 13.8 and every later line stood 1.1pt low.)
            // (A paragraph of a lone picture that wraps text round it is the mark's line and no more: the picture's run
            // carries no size of its own, and the 10pt of the style under it made dx2 bg ec25df03's header's 1pt first
            // paragraph 10.4pt too deep, every line of the page after it.)
            let pictureOnly = p.image?.float?.wraps == true && p.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC })
            bodyHeight = spacesOnly || p.image == nil || p.image?.textBox != nil || pictureOnly ? probe.height : max(bodyHeight, probe.height)
            probe.dispose()
        }
        // A tab at the paragraph's end whose stop lies past the right
        // edge of the text goes to a line of its own, as Word sets it —
        // minutes typed with a tab after each full stop are a line
        // longer wherever the sentence filled its line. The engine
        // hangs a tab at a line's end like a space.
        // Picture-only tab rows do not take that extra line: Word's
        // issue_51265_3 header ends at its pictures' baseline, with or
        // without its final tab.
        // (The same for a row of pictures and tabs, the line the tab opens being a
        // text line of the paragraph mark's own, not the pictures': dx2 es
        // 335fbcf8's header, a picture as wide as the text and a tab, its left
        // stop behind it, the next default one past the margin, stands 13pt deeper
        // in Word's print. issue_51265_3's trailing tab, whose right stop is the
        // margin, takes no line.)
        if theme.wordRules, p.image == nil, p.text.utf16.count > 1, p.text.utf16.last == 0x09,
           let lastLine = painter.computeLineMetrics().last {
            let units = Array(p.text.utf16)
            var k = units.count - 1
            while k > 0, units[k] == 0x09 || units[k] == 0x20 { k -= 1 }
            let at = _map(i).painter(k)
            if let box = painter.getBoxesForSelection(TextSelection(baseOffset: at, extentOffset: at + 1)).last {
                let x = ownLeft + box.right
                let step = _px(document.defaultTabStop ?? 36)
                // (A stop the pictures end on is reached: float equality, not a tolerance.)
                let reach = pictureTabs ? -0.01 : 0.5
                let stop = style.tabStops.map { _px($0.position) }.sorted().first(where: { $0 > x + reach })
                    ?? (step > 0 ? ((x + reach) / step).rounded(.down) * step + step : x)
                // (A right-aligned paragraph's trailing tab past the margin takes no line of its own: the
                // text stands flush right and the tab hangs, as the trailing spaces do. dx2 33a4668e's header, a
                // page number set right with a tab after it, one 13.4pt line in Word's print, ours two.)
                let hangsRight = theme.wordRules && RichTextTheme.wordWindowsPages && !pictureTabs && style.alignment == .right && !style.rightToLeft
                if hangsRight, stop > ownLeft + textWidth + 0.5 { RuleTrace.hit("word-right-aligned-trailing-tab-takes-no-line") }
                // (A left stop inside a table cell's full width, its text edge and both rules' halves, is on the line
                // Word draws the tab on: dx2 1469a400's underlined trailing tab at 11400 twips in a 11401-twip
                // cell, 9 twips past our text edge, took no second line in Word's print.)
                let cellRoom: Double = {
                    guard theme.wordRules, !pictureTabs, p.cell != nil, let c = p.cell, let ts = document.tableStyles[c.table], ts.borders,
                          style.tabStops.contains(where: { $0.alignment == .left && abs(_px($0.position) - stop) < 0.01 }) else { return 0 }
                    return _px(((ts.edgeWidths["right"] ?? ts.borderWidth ?? 0.5) + (ts.edgeWidths["left"] ?? ts.borderWidth ?? 0.5)) / 2)
                }()
                if cellRoom > 0, stop > ownLeft + textWidth + 0.5, stop <= ownLeft + textWidth + 0.5 + cellRoom {
                    RuleTrace.hit("word-trailing-left-tab-inside-the-cell-width-takes-no-second-line")
                }
                // (An EXPLICIT left stop past the margin, with the text still short of the margin, takes no line of its
                // own in Word's print: sa2 3c4382f0's "Eu, " + tab, stop 9683 twips in an 8504-twip measure, the next
                // paragraph one line below, ours two. A default stop past the margin, text at the margin, still does.)
                let explicitPast = theme.wordRules && RichTextTheme.wordWindowsPages && !pictureTabs && style.alignment == .justify && x < ownLeft + textWidth - 0.5
                    && style.tabStops.contains(where: { $0.alignment == .left && abs(_px($0.position) - stop) < 0.01 })
                if explicitPast, stop > ownLeft + textWidth + 0.5 { RuleTrace.hit("word-explicit-tab-stop-past-the-margin-takes-no-line") }
                // (A RIGHT stop past the margin, the paragraph ending in the tab: the stop is clamped to the margin, the tab fills
                // to it and ends the line, no line of its own. xd 6dd1ef35's footer "<tab>2<tab>March 2024<tab>" with a right stop
                // 226 twips past the margin, the text short of the margin (one already AT it still sends the tab down, sa-xd 8e81b68d's
                // footer cell): one line in Word's print, ours two, 10.4 pt taller, the page's table header pushed
                // to the next page. The same footer with that stop at or inside the margin, or a left stop, was already one line.)
                let rightClampedTab = theme.wordRules && RichTextTheme.wordWindowsPages && !pictureTabs && !style.rightToLeft && x < ownLeft + textWidth - 0.5
                    && style.tabStops.contains(where: { $0.alignment == .right && abs(_px($0.position) - stop) < 0.01 })
                if rightClampedTab, stop > ownLeft + textWidth + 0.5 + cellRoom { RuleTrace.hit("word-trailing-tab-at-a-right-stop-past-the-margin-takes-no-line") }
                if !hangsRight, !explicitPast, !rightClampedTab, stop > ownLeft + textWidth + 0.5 + cellRoom {
                    if pictureTabs {
                        var mark = p.style.mark ?? p.runs.first?.style ?? CharStyle()
                        mark.inlineImage = nil
                        let line = RichParagraph(text: " ", runs: [Run(length: 1, style: mark)], style: p.style)
                        let (span, _, _) = _span(for: line, at: nil, document, textWidth: textWidth)
                        let probe = TextPainter(text: span, textAlign: .left, textDirection: .ltr, strutStyle: _strut(span))
                        probe.fractionalLineHeights = theme.wordRules
                        probe.layout(minWidth: 0, maxWidth: max(1, textWidth))
                        bodyHeight += probe.height
                        probe.dispose()
                    } else { bodyHeight += lastLine.height }
                }
            }
        }
        // (A last line of spaces alone, wrapped below an inline picture in a paragraph of text and pictures, is the
        // paragraph mark's line when the mark is taller than the spaces: dx2 es 2f747ec3's 14pt bold mark after a
        // 475pt picture and 11pt spaces, the next paragraph 3.3pt lower in Word's print than ours.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.image == nil, p.cell == nil, p.inlineImages.inOrder.contains(where: { $0.float == nil && $0.textBox == nil }),
           abs(style.lineSpacing - 1) < 0.001, p.text.utf16.count > 1, p.text.utf16.last == 0x20,
           let lastLine = painter.computeLineMetrics().last, painter.computeLineMetrics().count > 1 {
            let units = Array(p.text.utf16)
            var k = units.count
            while k > 0, units[k - 1] == 0x20 { k -= 1 }
            let spacesAt = _map(i).painter(k)
            let end = _map(i).painter(units.count - 1) + 1
            if painter.getLineBoundary(TextPosition(offset: end - 1)).start >= spacesAt {
                let mark = _markLineHeight(i, document, single: true)
                if mark > lastLine.height + 0.2 {
                    RuleTrace.hit("word-spaces-only-last-line-takes-the-taller-paragraph-mark")
                    bodyHeight += mark - lastLine.height
                }
            }
        }
        // (No lines at all: `RichParagraphStyle.lineCollapsed`.)
        if theme.wordRules, style.lineCollapsed, p.image == nil { bodyHeight = 0 }
        if _markUnderNestedTable(i, document) { bodyHeight = 0 }
        // (An empty paragraph of an exact line height is that tall: the
        // engine gives a 0.7pt strut nothing, and zh-90e0cea8's two
        // counter paragraphs — 1pt text on 0.7pt exact lines, before
        // each annex heading — left the heading 1.4pt higher than Word's
        // print has it, and page 8's foot then held a row line more.)
        // (Not the mark under a nested table, which has none whatever its
        // spacing: zh-20c1d74a p18's, on an exact 20pt line, under its
        // 其他申請補助機關名稱 table — Word's row is its stated 116.85,
        // ours 20 more, and the page ran 14pt low from there.)
        if theme.wordRules, p.text.isEmpty, p.image == nil, !style.lineCollapsed, let exact = style.lineHeightPoints, exact > 0,
           !_markUnderNestedTable(i, document) {
            bodyHeight = max(bodyHeight, _px(exact))
        }
        @inline(never) func _blk8() {
        if let image = p.image {
            // Shown at its own size, shrunk to the column when wider —
            // except under Word's rules, where a picture keeps the size
            // the file gives it and runs past the margin (zh-06c46ba9's
            // fishbone chart, 419pt in a 401pt line, is drawn at 419 in
            // Word's print and 8pt taller than ours was).
            var w = _px(image.width)
            var h = image.float != nil ? _bodyBoxHeight(image, document) : _px(image.height)
            if w > textWidth, !theme.wordRules { h *= textWidth / w; w = textWidth }
            // (Or laid out again to the line's width, where it can be:
            // `objectFitter` — a display equation broken over lines.)
            if theme.wordRules, image.float == nil, image.data.isEmpty, w > textWidth + 0.5, textWidth > 0,
               let fit = Self.objectFitter?(image, textWidth / (theme.pixelsPerPoint * scale)) {
                w = _px(fit.width); h = _px(fit.height)
            }
            // (A table nested in a cell: as tall as it lays out.)
            if image.textBox?.growsToFit == true, let inside = _textBox(image, document) { h = inside.height + (theme.wordRules ? _px((image.textBox?.insetBottom ?? 0) + (image.textBox?.insetTop ?? 0)) : 0) }
            _imageSize[i] = Size(w.rounded(), h.rounded())
            // (Where its paragraph sets it: zh-9c5d0c3f's road signs stand
            // in the middle of their cells in Word's print, at the cells'
            // left in ours. One wider than the line keeps to its left.)
            // (Its line holds its character border and its effects too,
            // and the border stands beside it as well.)
            let room = theme.wordRules && image.float == nil ? _pictureRoom(image) : (top: 0.0, bottom: 0.0, left: 0.0, right: 0.0)
            _imageDrop[i] = room.top
            // (A picture on the first line stands in by the paragraph's first-line indent, as text
            // does: zh-b8de3ae2's 圖6 chart, 483.75pt under `w:firstLine` 660, has its title at
            // 185 in Word's print and 152 where ours stood without it. Centred, the room left is
            // shared out after the indent; right-aligned, the indent changes nothing.)
            let rawIndent = theme.wordRules && style.alignment != .right && image.float == nil && style.list == nil ? _px(p.style.firstLineIndent) : 0
            // (Not one as wide as the column or wider: zh-76700e5f's w:firstLine 31680 put the centred picture off the page; Word counts the style's characters instead, as for text.)
            var indent = rawIndent
            if RichTextTheme.wordWindowsPages, rawIndent >= textWidth, let chars = Double(p.style.eastAsian["w:firstLineChars"] ?? ""), chars > 0 {
                let size: Double = p.runs.first?.style.fontSize ?? _named(p, document)?.char.fontSize ?? theme.fontSize
                indent = _px(chars / 100 * size)
            } else if RichTextTheme.wordWindowsPages, rawIndent >= textWidth { indent = 0 }
            let spare = theme.wordRules ? max(0, textWidth - indent - w.rounded() - room.left - room.right) : 0
            // (Not its effect extent's left, in a frame placed on the page: the
            // drawing stands at the frame's x — lab frame.)
            let atFrameX = style.frame.map { $0.verticalAnchor == "page" && $0.horizontalAnchor == "page" } ?? false
            // (A right-to-left paragraph starts at the right: its object stands at the right end of the line, and one wider than the line
            // runs out past the left: xd bf53d2b7's 448.6pt text boxes in a 432pt column stood at 55.3 in Word's print, at 73.3 in ours.)
            let startsRight = RichTextTheme.wordWindowsPages && style.rightToLeft && image.float == nil && style.alignment != .center
            let rtlSpare = startsRight ? textWidth - indent - w.rounded() - room.left - room.right : spare
            _imageShift[i] = indent + (style.alignment == .center ? spare / 2 : style.alignment == .right ? (startsRight ? min(spare, rtlSpare) : spare) : startsRight ? rtlSpare : 0) + (atFrameX ? 0 : room.left)
            // A floating object stands clear of the flow: its paragraph
            // is the height of its (empty) line, as Word sets it.
            if theme.wordRules, let float = image.float, !float.takesRoom {} else { bodyHeight = (h + room.top + room.bottom).rounded() }
            // (A horizontal rule's paragraph is a line of its text: the
            // reader's "hr", lab `hr`.)
            if theme.wordRules, image.name == "hr" {
                // (An hr-only paragraph is the height of the rule's own run, at the paragraph's multiple, whatever size its mark
                // is: labs hronly 1-10, marks 8 to 20 all 53.5pt apart at 1.5 lines.)
                var own: CharStyle? = nil
                if RichTextTheme.wordWindowsPages, (document.compatibilityMode ?? 0) >= 15, let rpr = image.sourceRunPropertiesXML, let r = rpr.rangeOfSubstring("w:sz w:val=\""),
                   let half = Double(rpr[r.upperBound...].prefix(while: { $0 != "\"" })) {
                    RuleTrace.hit("hr-only-paragraph-is-the-height-of-the-rules-run")
                    var m = document.paragraphs[i].style.mark ?? document.paragraphs[i].runs.first?.style ?? CharStyle()
                    m.fontSize = half / 2
                    own = m
                }
                bodyHeight = max(bodyHeight, _markLineHeight(i, document, using: own))
            }
            // (In a line of an exact height a picture taller than it keeps
            // the line that tall, and stands on its baseline, rising over
            // the lines above: zh-ae2dd08d's flowchart, a 594pt inline
            // group in a cell's last paragraph of exact 23pt lines, is
            // drawn whole up the cell in Word's print and its four rows
            // stand at the 598pt their lines make; ours grew the line to
            // the picture, the row to 656pt, and it went over the page.)
            else if theme.wordRules, image.float == nil, image.textBox?.growsToFit != true, let exact = style.lineHeightPoints,
                    !style.lineHeightIsMinimum, exact > 0, h + room.top + room.bottom > _px(exact) + 0.5 {
                bodyHeight = _px(exact)
                // (Lowered as its run's `w:position` says, as on any line: zh-06c46ba9 p66's
                // 265.5pt outline group, in a 265.45pt exact line and a run at -52.5, has its
                // top at the line's in Word's print; ours stood it 52.5pt high.)
                // (A paragraph that is the picture alone keeps no run of it: the `w:position` is read from
                // the run's saved properties. zh-bdae17c0 p69's outline group, the same one as zh-06c46ba9 p66's
                // in a 265.45pt exact line at -52.5, stood 48pt high with the first two lines of its text cut off.)
                let lowered = p.runs.first(where: { $0.style.inlineImage == image.id }).flatMap { $0.style.raised } ?? Self._runPosition(image.sourceRunPropertiesXML) ?? 0
                _imageDrop[i] = _px(exact * 4 / 5) - h - room.bottom - _px(lowered)
            }
            // (A picture shorter than its paragraph's line of text stands
            // at the foot of that text's own line, which the line takes
            // the height of. drawing.docx's 4.5pt spacer under five empty
            // paragraphs stands 5.85pt down a 10.35pt line of its 9pt
            // Times mark in Word's print, and the next line starts at
            // the picture's foot (the Mac's lab t50: a 12pt mark lowers
            // both by 3.45, and a picture taller than the line is its
            // own height). bug59058's 11.25pt one under an 11pt Calibri
            // mark stands 2.18pt down, the single line's 13.43; what the
            // paragraph's 1.15 lines add goes under it, as under text.
            // Ours was the picture's height alone, and drawing's page 9
            // opened 5.8pt high. Off the line grid, which sets a
            // picture's line its own way.)
            else if theme.wordRules, image.float == nil, image.textBox == nil, style.lineHeightPoints == nil || style.lineHeightIsMinimum,
                    _grid(i, document).pitch == nil || _offGrid(i, document) {
                // (Under an "at least" height the picture's line is that height, not the mark's line of text:
                // jpn-g5-b79900's 2pt rule alone in a paragraph of at least 12pt is a 12pt line in Word's
                // print, a 14.4pt mark's line would put the next paragraph 2.6pt low.)
                let line = (style.lineHeightIsMinimum ? style.lineHeightPoints.map { _px($0) } : nil) ?? _markLineHeight(i, document, single: true)
                let own = h + room.top + room.bottom
                if line > own + 0.5 {
                    _imageDrop[i] += line - own
                    bodyHeight = (bodyHeight + line - own).rounded()
                }
                // (An underlined picture taller than its mark's line, under Word for Windows: the line keeps the
                // mark's descent under the picture's foot. b66c721a's 72.9pt picture over a 14pt
                // mark puts the next line 3.65pt (0.26 em) lower in Word's print, 7.36 at 28pt; lab: underline off moves the title up 3.84, bold off changes nothing.)
                else if RichTextTheme.wordWindowsPages, p.image != nil,
                        ((p.runs.first(where: { $0.style.inlineImage == image.id })?.style.underline ?? false)
                         || ((image.sourceRunPropertiesXML?.containsSubstring("<w:u ") ?? false) && !(image.sourceRunPropertiesXML?.containsSubstring("w:val=\"none\"") ?? false))) {
                    // (The picture's OWN run underlined: an underlined mark alone changes nothing; lab bookman1, 0d2c40e4.)
                    let drop = _markLineHeight(i, document, single: true, descentOnly: true)
                    if drop > 0 {
                        RuleTrace.hit("picture-line-mark-descent")
                        bodyHeight = (bodyHeight + drop).rounded()
                    }
                }
            }
            // (A picture as wide as the line leaves its paragraph mark no
            // room, and the mark opens a line of its own under it: lab
            // `wide`, an object of 456.75pt in a column of 456.75 puts the
            // next paragraph a 12pt Times line lower in Word's print, one
            // of 456.7 does not. WordWithAttachments' 468pt document
            // object in its 467.75pt column. Ours set the mark beside it.
            // An embedded object's only: a DrawingML picture keeps its mark
            // beside it, bug57031's 480pt plots in a 468pt column.)
            if theme.wordRules, image.float == nil, image.textBox == nil, image.name == "w:object", p.cell == nil,
               w + _px(0.01) >= textWidth {
                bodyHeight = (bodyHeight + _markLineHeight(i, document)).rounded()
            }
            _ensureDecoded(image)
        } else {
            _imageSize[i] = nil
            _imageShift[i] = 0
            _imageDrop[i] = 0
        }
        }
        _blk8()
        // A line holding a picture keeps to the line grid too: as many
        // whole pitches as it needs, the rest above the picture. (The
        // engine sets no strut on such a line, so nothing snapped it:
        // zh-9c5d0c3f's road signs, 75pt in a line of 90 on an 18pt grid,
        // stood 10pt high in rows 15pt short. In the body as in a cell —
        // lab `pg`, 2026-10-14: zh-90e0cea8's 25pt picture takes a line
        // of 31.2, two of them 62.4, and under `w:snapToGrid` off 25.5.)
        // (Two lines in one, `_span`'s box for them, are text on the
        // grid: as many pitches as the box needs, and centred in them —
        // zh-454e2e29's title, 41.3pt of combined 24pt text in a line of
        // three 18pt pitches, its baseline 37.2 down in Word's print.)
        let combined = inline.contains { $0.image?.name == "combine" } && painter.computeLineMetrics().count == 1
        // (Not a table nested in a cell: a block, not a line.)
        let inLine = p.image.map { $0.float == nil && $0.textBox?.growsToFit != true }
            ?? ((p.inlineImages.values.contains { $0.float == nil && $0.baseline == nil } || combined) && painter.computeLineMetrics().count == 1)
        // (An object with a baseline of its own — an equation — is set as
        // text is, not snapped as a picture: zh-c2c92639's "式中：C_dm ——…"
        // lines are one pitch of its grid in Word's print, ours two.)
        // (An "at least" height keeps to the grid as a picture's line
        // does, the picture being more than the least: zh-9c5d0c3f's
        // fifth column, a 58.5pt sign in a paragraph of at least 19.2pt
        // on an 18pt grid, takes four pitches in Word's print, 7.5pt of
        // them over the sign — ours had set it flush and its captions
        // 14pt high. Only an exact height leaves the grid.)
        @inline(never) func _blk9() {
        if theme.wordRules, inLine, style.lineHeightPoints == nil || style.lineHeightIsMinimum,
           !_offGrid(i, document), let pitch = _grid(i, document).pitch, pitch > 0 {
            let px = _px(pitch)
            // (The descent of a picture paragraph's mark: what of its line
            // may hang past a page's foot. Word's 25pt picture ends 3.4pt
            // above its 31.2pt line's foot.)
            let descent = p.image != nil ? (painter.computeLineMetrics().first?.descent ?? 0) : 0
            // (As many pitches as the picture is tall, its descent not
            // counted: lab `pg2` in zh-9c5d0c3f's package (Word 16, an
            // 18pt grid, mode 12) gives a 54pt sign three pitches, 57 to
            // 72 four and 73 five, under "at least" 19.2 too; with the
            // descent counted ours gave 54 four and 69-72 five, and the
            // road signs' rows ran a pitch tall.)
            let snapped = ((bodyHeight + (p.image != nil ? 0 : descent)) / px - 0.002).rounded(.up) * px
            // (Pictures in a line of text: as many pitches as the tallest
            // picture is tall, the text's descent not counted. Lab `pic3`
            // (Word 16 Mac, zh-76700e5f's package, a 15.6pt grid): three
            // pictures in a centred paragraph of spaces take four pitches
            // up to 62pt and five from 63; ours counted the line's descent
            // and took five from 58.5, the document's own figure 4, and
            // every page after it ran a line late.)
            let tallest = (painter.inlinePlaceholderBoxes ?? []).map { $0.bottom - $0.top }.max() ?? 0
            // (Two lines in one take the pitches their box needs, not the
            // text's: each run of the line is its own whole pitches, its
            // baseline where its face puts it, and the box's foot under
            // that runs past them. zh-454e2e29's page-4 title, a 31.22pt
            // box of DFKai-SB's two 12pt lines beside 18pt text, is two 18pt
            // pitches in Word for Windows' print, the box centred in them;
            // ours, the text's 28.85 over the baseline and the box's 8.37
            // under, was 37.2 and took three, and the page ran 16pt low.)
            let boxes = combined && p.inlineImages.isEmpty ? (painter.inlinePlaceholderBoxes ?? []) : []
            let boxTop = boxes.map { $0.top }.min() ?? 0, boxFoot = boxes.map { $0.bottom }.max() ?? 0
            let boxPitches = ((boxFoot - boxTop) / px - 0.002).rounded(.up) * px
            // A picture shorter than the text's own baseline must not
            // shrink that text to the picture's grid pitches. Keep the
            // ordinary text line and baseline when it contains the picture.
            var textFloor: (height: Double, inkShift: Double)?
            let named = _named(p, document)
            if p.image == nil, !combined, !Self._risesForNumber(inline),
               ["auto", "baseline"].contains(style.eastAsian["w:textAlignment"] ?? "auto"),
               p.inlineImages.values.allSatisfy({ $0.textBox == nil && $0.float == nil && $0.baseline == nil }),
               p.runs.allSatisfy({ $0.style.script == .normal && ($0.style.raised ?? named?.char.raised ?? 0) == 0 }),
               !p.text.contains(where: { $0 != "\u{FFFC}" && Self.isEastAsian($0, hinted: true) }),
               let textStrut = _strut(span, tallest: true, near: spacedOver || thaiNear, wide: thaiNear),
               let size = textStrut.fontSize, let height = textStrut.height,
               let line = painter.computeLineMetrics().first {
                var naturalStyle = style
                naturalStyle.lineHeightPoints = nil
                var best = -Double.infinity
                var baseline: Double?
                var at = p.text.utf16.startIndex
                for run in p.runs {
                    let end = p.text.utf16.index(at, offsetBy: run.length)
                    defer { at = end }
                    guard run.style.inlineImage == nil,
                          (run.style.fontHint ?? named?.char.fontHint) != "eastAsia",
                          !p.text[at ..< end].allSatisfy(Self._setsNoLine),
                          let own = theme.baseline(for: run.style, in: naturalStyle, named: named, eastAsian: false, gridPitch: pitch, centresInLine: document.spacesForUnderline),
                          let placed = theme.baseline(for: run.style, in: style, named: named, eastAsian: false, gridPitch: pitch, centresInLine: document.spacesForUnderline) else { continue }
                    if own > best { best = own; baseline = placed }
                }
                if let baseline, tallest <= _px(baseline) + 0.01 {
                    textFloor = (size * height, _px(baseline) - line.baseline)
                }
            }
            if let textFloor {
                bodyHeight = max(textFloor.height, (tallest / px - 0.002).rounded(.up) * px)
                _inkShift[i] = textFloor.inkShift
            } else if p.image == nil, !combined, tallest > px + 0.01 {
                let own = (tallest / px - 0.002).rounded(.up) * px
                // (On a snapToChars grid the spare room is split evenly above and below the
                // picture, the text's descent not counted: xb jpn 837e72c4's GR16f, a 20pt
                // picture in 36pt on an 18pt grid, stands 8pt from each edge in Word's print,
                // where ours put all 13 above it.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, _gridCellBase(i, document) != nil, own > tallest + 0.01,
                   !p.text.unicodeScalars.filter({ $0.value != 0xFFFC }).isEmpty {
                    RuleTrace.hit("word-snapchars-picture-line-centred")
                    _inkShift[i] += (own - tallest) / 2
                } else {
                    _inkShift[i] += own - bodyHeight
                }
                bodyHeight = own
            } else if !boxes.isEmpty, boxPitches < bodyHeight - 0.01 {
                _inkShift[i] += (boxPitches - (boxFoot - boxTop)) / 2 - boxTop
                bodyHeight = boxPitches
            } else if snapped > bodyHeight + 0.01 {
                // (A picture's own paragraph centres it, effects and all, in
                // its pitches: zh-547fc43c's charts and pictures stand half
                // their lines' spare room down in Word's print — 7.05pt of a
                // 14.1 — where under the rest less the descent its 233.75pt
                // chart stood 3.6pt low and its 219pt picture 3.4.)
                _inkShift[i] += (combined && p.inlineImages.isEmpty) || p.image != nil ? (snapped - bodyHeight) / 2
                    : max(0, snapped - bodyHeight - descent)
                bodyHeight = snapped
            }
            // (At a page's foot the picture itself must fit; the descent
            // under it may hang past: zh-90e0cea8's last picture ends at
            // the foot of its page in Word's print, its line 2.6pt past.)
            if p.image != nil, i < _overhang.count { _overhang[i] = max(_overhang[i], descent) }
        } else if theme.wordRules, p.image == nil, !_picturesTakeLines(p, textWidth: textWidth), p.inlineImages.values.contains(where: { $0.float == nil && $0.baseline == nil }),
                  style.lineHeightPoints == nil, !_offGrid(i, document),
                  let pitch = _grid(i, document).pitch, pitch > 0,
                  case let lines = painter.computeLineMetrics(), lines.count > 1,
                  let box = painter.inlinePlaceholderBoxes?.first(where: { $0.bottom - $0.top > 0.01 }), box.bottom <= lines[0].height + 0.5 {
            // (… and a picture on the first line of several, the extra
            // above it as well: zh-9c5d0c3f's fifth column holds its sign,
            // a break and its caption in one paragraph, and Word stands
            // the sign level with the others' on their 90pt lines, where
            // ours stood 11pt higher.)
            // (On its baseline with the text's descent under it, as above:
            // the text's, from the line after it — the picture's own line
            // has none, and the sign then stood 4pt below its row's.)
            let px = _px(pitch)
            let first = lines[0].height, descent = max(lines[0].descent, lines[1].descent)
            // (The picture's own line is counted alone, not with the text's
            // descent: xb jpn 7f0539's Figure 4, 324.0pt on an 18pt grid, is
            // 18 pitches in Word's print, not 19.)
            let snapped = (first / px - 0.002).rounded(.up) * px
            if snapped > first + 0.01 {
                _inkShift[i] += max(0, snapped - first - descent)
                bodyHeight += snapped - first
            }
        } else if theme.wordRules, p.image == nil, !_picturesTakeLines(p, textWidth: textWidth), p.inlineImages.values.contains(where: { $0.float == nil && $0.baseline == nil }),
                  style.lineHeightPoints == nil || style.lineHeightIsMinimum, !_offGrid(i, document),
                  let pitch = _grid(i, document).pitch, pitch > 0,
                  case let lines = painter.computeLineMetrics(), lines.count > 1, let last = lines.last,
                  let box = painter.inlinePlaceholderBoxes?.last(where: { $0.bottom - $0.top > 0.01 }), box.top >= lines.dropLast().reduce(0, { $0 + $1.height }) - 0.5,
                  last.height > _px(pitch) * 2 {
            // (… and a picture on the last line of several, below the text
            // before it: its line too is as many pitches as it takes, the
            // rest left under it. zh-e49d7943's title "…演習編組表" has its
            // 660.55pt picture after it in the same paragraph, on page 15
            // alone in Word's print, its line 37 18pt pitches — 666 — and
            // the empty paragraph and the next table's title row after it
            // run past the foot to page 16; ours, the picture's own
            // 660.7, kept that row on page 15.)
            let px = _px(pitch)
            let snapped = (last.height / px - 0.002).rounded(.up) * px
            if snapped > last.height + 0.01 { bodyHeight += snapped - last.height }
        } else if theme.wordRules, inLine, style.lineHeightPoints == nil, _grid(i, document).pitch == nil || _offGrid(i, document),
                  case let multiple = style.lineSpacing - theme.lineSpacingReduction,
                  multiple > 1.001 || (multiple < 0.999 && multiple > 0.1) || (p.image == nil && p.style.eastAsian["w:textAlignment"] == "bottom" && _hasVisibleText(p)) {
            // Off the grid, a multiple on a picture's line adds what it
            // adds to its mark's single line, under the line — not a
            // multiple of the picture, and not lost under it, as the
            // engine's height was. Lab `hp` (Word for Windows, Bug51170's
            // 78pt logo alone in a header paragraph, Calibri 11): the text
            // after it 2.04 lower at 1.15 lines than at single, 13.44
            // lower at 2 — with or without text beside the picture.
            // (Off a grid the section has, too: lab `pn` (Word 16 Mac,
            // zh-e68a2f57's package), its p7 chart alone in a paragraph of
            // 1.1 lines, snapToGrid 0, under a 9pt 黑体 mark — the note
            // after it 1.20 lower than at single, 0.1 of the mark's line,
            // whatever the picture run's size; ours added nothing there.)
            var single = _markLineHeight(i, document) / multiple
            if p.image == nil, let t = _tallestTextLine(i, document), t > single {
                // (Picture plus text on the line: the multiple scales the tallest text's line — lab picline1, 11pt Malgun, 19.0 a unit against the mark's 11.5.)
                RuleTrace.hit("picture-line-multiple-of-text")
                single = t
            }
            if p.image?.name == "hr" {
                // (A horizontal rule's line is the mark's line, set above at the paragraph's multiple already:
                // jpn-z22306877-1047a4's rule at 1.25 stood 3.9pt, a quarter of the line, low in ours.)
            } else if p.image != nil {
                // (A picture alone whose own run states no size, face or style, under a paragraph mark that does: the multiple's extra
                // is that of the style's own line, not the mark's. dx2 01838920's 347pt picture over a 39pt Comic Sans mark at 1.08
                // lines: the title 1.1pt under it in Word's print, the 11pt Calibri line's 1.06, where the mark's added 4.3.)
                var extra = single
                if RichTextTheme.wordWindowsPages, p.style.mark != nil, let image = p.image, let rpr = image.sourceRunPropertiesXML,
                   !rpr.containsSubstring("w:sz ") && !rpr.containsSubstring("w:rFonts") && !rpr.containsSubstring("w:rStyle") {
                    RuleTrace.hit("picture-alone-multiple-extra-of-the-styles-line")
                    extra = _markLineHeight(i, document, single: true, using: CharStyle())
                } else if RichTextTheme.wordWindowsPages, (document.compatibilityMode ?? 0) >= 15, p.cell == nil, let image = p.image, image.name != "w:object",
                          let rpr = image.sourceRunPropertiesXML, let r = rpr.rangeOfSubstring("w:sz w:val=\""),
                          let half = Double(rpr[r.upperBound...].prefix(while: { $0 != "\"" })) {
                    // (A picture alone whose own run states a size: the multiple's extra is that run's line, not the mark's, as under a
                    // picture and a rule: lab hrimg F, a 100x50pt picture in an 8pt run over a 20pt mark at 1.5 lines, the next line
                    // 93.9 down in Word's print, 101.7 with the mark's extra.)
                    RuleTrace.hit("picture-alone-multiple-extra-of-its-runs-line")
                    var m = p.style.mark ?? p.runs.first?.style ?? CharStyle()
                    m.fontSize = half / 2
                    extra = _markLineHeight(i, document, single: true, using: m)
                }
                bodyHeight += (multiple - 1) * extra
                // (A picture alone keeps its line but its ink rises by the cut as well: lab kopic3 D, 0.929 lines, Word 88.41, ours 89.87.)
                if RichTextTheme.wordWindowsPages, multiple < 0.999, multiple > 0.1, p.cell == nil {
                    RuleTrace.hit("word-picture-alone-under-a-multiple-below-one-rises-by-the-cut")
                    _inkShift[i] -= (1 - multiple) * extra
                }
                // (A multiple's extra under a picture alone hangs past a page's foot as under text: sa1 c11d31f3's chart,
                // 1.5 lines, stays on page 3 in Word's print with its extra 6.7pt over the margin, even 2pt taller.)
                if theme.wordRules, multiple > 1.001, i < _overhang.count, p.cell == nil {
                    RuleTrace.hit("picture-alone-multiple-extra-hangs-past-the-foot")
                    _overhang[i] = max(_overhang[i], (multiple - 1) * extra)
                }
            } else if !(style.rightToLeft && Self._paired(painter)?.objects == true), case let lines = painter.computeLineMetrics(), lines.count == 1,
                      let box = painter.inlinePlaceholderBoxes?.max(by: { $0.bottom - $0.top < $1.bottom - $1.top }),
                      box.bottom - box.top >= lines[0].ascent - 0.5 {
                // (The engine scales the text's descent by the multiple
                // and nothing else: Word keeps its single descent.)
                let target = (box.bottom - box.top) + lines[0].descent / multiple + (multiple - 1) * single
                bodyHeight += max(0, target - lines[0].height)
                _pictureTextLineAdjust(i, p, multiple: multiple, single: single, bodyHeight: &bodyHeight)
                // (Word keeps the baseline where single spacing puts it, the extra all under it; the engine put its share above the picture: lab picline1, 146be6fb.)
                if box.top > 0.05, !p.text.isEmpty { RuleTrace.hit("picture-line-extra-all-below"); _inkShift[i] -= box.top; bodyHeight -= box.top }
            }
        } else if theme.wordRules, RichTextTheme.wordWindowsPages, p.image == nil, p.cell == nil, !_hasVisibleText(p),
                  style.lineHeightPoints == nil, _grid(i, document).pitch == nil || _offGrid(i, document),
                  case let multiple = style.lineSpacing - theme.lineSpacingReduction, multiple <= 1.001, multiple > 0.1,
                  p.inlineImages.values.filter({ $0.float == nil && $0.baseline == nil }).count == 1,
                  p.inlineImages.values.contains(where: { $0.float != nil }),
                  case let lines = painter.computeLineMetrics(), lines.count == 2 {
            // (Floating shapes ahead of an inline picture, and spaces or nothing else: the floats make no line, the picture's line is
            // the paragraph's last, and under a multiple below 1 every line with a picture and no visible text loses (1 - multiple) of
            // the paragraph mark's single line off its top, so the picture stands that much higher: lab kopic3 (Word for Windows),
            // 11 cases, dx2 ko 1f6d638c. A 363pt picture after an anchor line, 0.929 lines over a 20.75pt Malgun Bold mark: the next line
            // 1.44 up, the picture 1.47; a 2-line paragraph (spaces, picture) over a 13pt mark takes the cut twice, once in the engine's
            // line of spaces. Ours had set an empty anchor line 0.9pt high.)
            RuleTrace.hit("word-picture-line-under-a-multiple-below-one-loses-its-top")
            bodyHeight = lines.reduce(0) { $0 + $1.height }
            if multiple < 0.999 {
                let cut = (1 - multiple) * _markLineHeight(i, document, single: true)
                bodyHeight -= cut
                _inkShift[i] -= cut
            }
        } else if theme.wordRules, p.image == nil, p.inlineImages.count == 1, p.inlineImages.values.allSatisfy({ $0.float == nil }),
                  style.lineHeightPoints == nil || style.lineHeightIsMinimum,
                  !(inLine && !_offGrid(i, document) && _grid(i, document).pitch != nil),
                  style.lineSpacing - theme.lineSpacingReduction <= 1.001,
                  p.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC || $0.value == 0x20 }),
                  case let lines = painter.computeLineMetrics(), lines.count == 1,
                  let box = painter.inlinePlaceholderBoxes?.first(where: { $0.bottom - $0.top > 0.01 }), box.bottom - box.top >= lines[0].ascent - 0.5 {
            // (A picture with only spaces after it is the picture's
            // paragraph still: the spaces add no descent under it. Lab
            // `ps` (Word 16, mode 15, zh-9c5d0c3f's 75pt road sign and its
            // trailing space): the caption under it stands where it does
            // with no space, 15.07pt under the picture's foot to its
            // baseline — ours 15.10 alone and 19.19 with the space.)
            bodyHeight = (box.bottom - box.top).rounded()
        }
        // (A picture and a horizontal rule in one paragraph: the picture's line takes the multiple's extra too, half
        // a line of the run's text at 1.5, whatever the paragraph mark's size. Word's print, lab hrimg A, B: the
        // line after stands 4.66pt lower than the engine set it, the same with an 8pt and a 20pt mark.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.image == nil, p.cell == nil, style.lineHeightPoints == nil,
           case let multiple = style.lineSpacing - theme.lineSpacingReduction, multiple > 1.001,
           p.inlineImages.values.filter({ $0.float == nil }).count == 2, p.inlineImages.values.contains(where: { $0.name == "hr" && $0.float == nil }),
           p.inlineImages.values.contains(where: { $0.name != "hr" && $0.float == nil && $0.textBox == nil && $0.baseline == nil }),
           p.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC || $0.value == 0x0A }),
           _grid(i, document).pitch == nil || _offGrid(i, document),
           painter.computeLineMetrics().count == 2, let hrRun = p.runs.first(where: { $0.style.fontSize != nil }) {
            RuleTrace.hit("word-picture-and-rule-line-takes-the-multiples-extra")
            // (A picture whose own run states no size takes the extra of the style's own line, as a picture alone does: dx2 48e5a592's
            // 210pt picture, its run stating only an East Asian face, over an 8pt Tahoma rule and a 20pt mark, in a 12pt Calibri Light style
            // at 1.5 lines: the next paragraph 7.31pt lower than single in Word's print, half the style's line, not the rule run's 4.83.)
            let pictureRun = p.inlineImages.values.first(where: { $0.name != "hr" && $0.float == nil })?.sourceRunPropertiesXML
            if let pictureRun, !pictureRun.containsSubstring("w:sz ") {
                RuleTrace.hit("word-picture-and-rule-line-extra-of-the-styles-line")
                bodyHeight += (multiple - 1) * _markLineHeight(i, document, single: true, using: CharStyle())
            } else {
                bodyHeight += (multiple - 1) * _markLineHeight(i, document, single: true, using: hrRun.style)
            }
        }
        }
        _blk9()
        // (A paragraph that ends in a line break ends with a line of its
        // mark alone, as tall as the mark's own line: zh-17749c13's
        // paragraph of one bold 仿宋_GB2312 break (YaHei to Word, two
        // 15.6pt pitches) under a 12pt 宋体 mark is three pitches in
        // Word's print — the break's two and the mark's one — where the
        // grid's strut set both lines two, and its page ran a pitch long.)
        if theme.wordRules, p.text.unicodeScalars.last == "\n" || p.text.unicodeScalars.last == "\u{2028}",
           style.mark != nil || (RichTextTheme.wordWindowsPages && p.image == nil),
           style.lineHeightPoints == nil, case let lines = painter.computeLineMetrics(), lines.count >= 2, let last = lines.last {
            // (A paragraph whose mark states nothing: its last line is the style's own, not the first run's.)
            var own = style.mark != nil ? _markLineHeight(i, document) : _markLineHeight(i, document, using: CharStyle())
            // (A mark in Mangal (or Nikosh, which Windows lacks) is Mangal's tall line, 1.68 em, as an empty paragraph's is, not the Latin line the
            // probe holds: hin-z10093577's abstract ends in an Arial break over a bold Mangal mark, and Word's print has the keyword line 33 pt under
            // the last text line, a 16.8 pt empty line and the 16.8 pt line, where ours cut the empty one to 11.5 and stood 5 pt high.)
            var raisedToMangal = false
            if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, let mark = style.mark,
               case let face = (mark.fontFamily ?? _named(p, document)?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased(),
               face == "mangal" || face == "nikosh"
                   // (SolaimanLipi, missing on Windows, in a Bengali paragraph: the empty line after a trailing break is Mangal's 1.68 em with or without a mark in the paragraph (it was 1.49 em
                   // without one, which left the next paragraph 3.9 pt high): xd 73caaeda's headings, p3 heading to next paragraph 38.0 in Word's print, ours 34.1 then 36.3.)
                   || (face == "solaimanlipi" && p.text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF && $0.properties.isAlphabetic })),
               let m = Self._indicLines["mangal"],
               let pt = mark.fontSize ?? _named(p, document)?.char.fontSize ?? _normalChar(document)?.fontSize {
                own = max(own, _px((m.0 + m.1) * pt))
                raisedToMangal = face == "solaimanlipi"
            }
            if last.height - own > 0.5 { bodyHeight -= last.height - own }
            else if raisedToMangal, own - last.height > 0.5 { bodyHeight += own - last.height }
        }
        _leadingBreakCut(i, p, painter, document, bodyHeight: &bodyHeight)
        // (Its own fraction too where its lines keep theirs: Word adds
        // its paragraphs' heights unrounded, and a page of one-line
        // paragraphs each rounded up stood a unit a paragraph long.)
        var total = before + push + bodyHeight + after
        // (A row flattened into paragraphs is as tall as the row asks, the
        // room it lacks under its last paragraph: see `blockMinHeight`.)
        if theme.wordRules, let least = style.blockMinHeight, p.cell != nil {
            var held = total
            var k = i - 1
            while k >= 0, k > i - style.blockParagraphs { held += _heights[k]; k -= 1 }
            if _px(least) > held { total += _px(least) - held }
        }
        // (In a table's cell, the empty line that carries a picture or chart wrapped square
        // across the whole of the cell's width — no room for three ems beside it — is set
        // under it, and the row holds that: lo-9fa3dedd's 280pt chart in a 267pt cell stands
        // 155 to 303 in Word's print and the line at 302, the row's foot 326; ours ended the
        // row at the line beside the chart's top.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.cell != nil, let cell = _cells[i],
           p.text.unicodeScalars.allSatisfy({ $0 == "\u{FFFC}" || $0 == "\n" }) {
            var images: [ImageAttachment] = []
            if i < _floatImages.count, let image = _floatImages[i] { images.append(image) }
            if i < _inline.count { images += _inline[i] }
            let inner = cell.colWidth - cell.pad.left - cell.pad.right
            let size = _px(_named(p, document)?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize)
            var down = 0.0
            var under = 0.0   // a picture with the text kept above and below it: the line stands under it
            for image in images {
                // (A picture wrapped top and bottom, alone in its paragraph in a cell: the empty line is set
                // under it, as the square one's above. lo-eb12e7d4's picture cells, 72pt pictures at 6.3pt and
                // at the top of the paragraph, have the row 245 - 147 = 98pt tall in Word's print and the line
                // at 226, 7pt under the lower picture; ours ended the row at the picture's foot.)
                if let float = image.float, float.takesRoom || float.bandsPage, !float.wraps, float.verticalFrom == "paragraph",
                   float.wrapSide == nil, !image.data.isEmpty || Self.drawsObject?(image) == true {
                    let y = float.verticalAlign == nil ? _px(float.y) : 0
                    // (One that starts below the paragraph's own line leaves the line where it is: the lines after it meet the picture,
                    // `_cellBandPush`. dx2 9d7e8c61's three small pictures 13 to 58pt under an empty 11pt line.)
                    if RichTextTheme.wordWindowsPages, float.verticalAlign == nil, y >= before + _markLineHeight(i, document) - 0.01 { RuleTrace.hit("word-cell-picture-below-its-own-line-leaves-the-line"); continue }
                    under = max(under, y + _bodyBoxHeight(image, document) + _px(float.effectBottom) + _px(float.distanceBottom))
                    continue
                }
                guard let float = image.float, float.wraps, !float.takesRoom, float.wrapSide == nil || float.wrapSide == "both",
                      float.verticalAlign == nil, float.verticalFrom == "paragraph", float.horizontalAlign == nil,
                      float.horizontalFrom == "column" || float.horizontalFrom == "cell",
                      image.sourceXML?.containsSubstring("drawingml/2006/chart") == true
                        || (image.textBox?.growsToFit == true && float.fromCellText && !float.fromCellTop) else { continue }
                let x = _px(float.x), w = _px(image.width)
                // (The empty line needs only its mark: 26pt beside lo-4d273731's chart in a 439pt cell is room
                // enough in Word's print, the row 196 tall; a chart as wide as the cell, none.)
                guard w > 0, x - _px(float.distanceLeft ?? 9) < size, inner - (x + w + _px(float.distanceRight ?? 9)) < size else { continue }
                down = max(down, _px(float.y) + _bodyBoxHeight(image, document) + _px(float.effectBottom) + _px(float.distanceBottom))
            }
            if under > 0.01, theme.wordRules {
                let line = _markLineHeight(i, document)
                if before + under + line + after > total + 0.01 {
                    RuleTrace.hit("word-cell-line-under-a-top-and-bottom-picture")
                    total = before + under + line + after
                }
            }
            if down > 0.01, before + down + bodyHeight + after > total + 0.01 {
                RuleTrace.hit("word-cell-line-carrying-a-full-width-square-float-is-set-under-it")
                total = before + down + bodyHeight + after
            }
        }
        total += _tamilMarkedLinesExtra(i, p, document, painter)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.eastAsian["w:fieldMarkDefault"] == "1", p.cell == nil, p.image == nil,
           style.lineHeightPoints == nil, abs(style.lineSpacing - theme.lineSpacingReduction - 1) < 0.001 {
            // (A marker with no rPr of its own is in the paragraph's style, whose size and face the paragraph's other runs get too: zh-0513f641's
            // footer page number sits in the 9pt footer style, not the 12pt Normal, and was grown to 12 by measuring Normal.)
            let line = _markLineHeight(i, document, single: true, using: CharStyle())
            if before + line + after > total + 0.01 {
                RuleTrace.hit("word-field-mark-in-default-font-counts-in-the-line")
                total = before + line + after
            }
        }
        _heights[i] = painter.fractionalLineHeights ? total : total.rounded(.up)
        // An empty paragraph that only ends a section stands for the
        // break and takes no room, as Word sets it.
        // (… and so does one that holds nothing but objects floating
        // clear of the text: zh-e0ca7252's equipment lists end their
        // sections in a paragraph of one text box, wrapNone, its note
        // set 17pt below; Word keeps the paragraph on the list's page,
        // the box hanging past the margin, where ours took it a line
        // and it opened a page of its own.)
        func clear(_ image: ImageAttachment) -> Bool { image.float.map { !$0.takesRoom && !$0.wraps } ?? false }
        let onlyFloats = p.image.map(clear)
            ?? (!p.text.isEmpty && !p.inlineImages.isEmpty && p.text.unicodeScalars.allSatisfy { $0 == "\u{FFFC}" }
                && p.inlineImages.values.allSatisfy(clear))
        // (Not where the next section goes on down the same page: there
        // the mark is a paragraph like any other, its space and its line —
        // zh-b8de3ae2's chart 10 has three empty marks of continuous
        // sections under its source line, 19.6, 5.9 and 16.0pt in Word
        // for Windows' print, the body's first baseline 502.27 to their
        // sum's 502.3; ours gave them none and ran a line high to p27.)
        // (Only where its section holds nothing else, lab t197: with a
        // line of text in 266's section Word gives 266 no room at all.)
        if theme.wordRules, (p.text.isEmpty && p.image == nil) || onlyFloats, style.sectionXML != nil, p.cell == nil,
           !(RichTextTheme.wordWindowsPages && style.ignoredSectionPageBreak),
           !(RichTextTheme.wordWindowsPages && style.sectionBreaksPage == false && !onlyFloats
             && (i == 0 || document.paragraphs[i - 1].style.sectionXML != nil)) { _heights[i] = 0 }
        // (So does a floating table nested in a cell: Word gives it no
        // paragraph of its own, only its place — see the reader's
        // `w:tblpPr`.)
        if theme.wordRules, p.cell != nil, let image = p.image, image.name == "table", image.float != nil { _heights[i] = 0; _spaceBefore[i] = 0 }
        // (An empty paragraph in a cell whose own picture, wrapped top and bottom, stands down its line and
        // reaches into it is set under the picture: Word's print of sa2 3c4382f0's signature rule, drawn 13.6pt
        // down an empty 13.8pt line, puts the next line 14.28pt lower — the picture's foot, then the line.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.cell != nil, p.text.isEmpty, !_vanishes(p, document),
           let own = p.image, let f = own.float, f.fromVMLLine, f.takesRoom || f.bandsPage, f.verticalFrom == "paragraph", f.verticalAlign == nil,
           f.y > 0.01, _px(f.y) < _heights[i] - _spaceBefore[i] {
            RuleTrace.hit("word-empty-cell-line-with-its-own-band-stands-under-it")
            _heights[i] += _px(f.y + own.height + f.effectBottom)
        }
        // (So does one wholly hidden, its mark too: see `_vanishes`.)
        if _vanishes(p, document) { _heights[i] = 0; _spaceBefore[i] = 0 }
        // (And, in Word for Windows, an empty paragraph straight after a
        // table floating by the text, where the strip beside the table
        // holds a character of its mark: Word sets it there, at the
        // table's side, and the text after it goes on under the table.
        // windows' lab pf: zh-7eba7349's "…2023年10月7日印发" table, 420.7pt
        // wide at tblpX 5.4 and 9pt clear on its right, has its empty
        // 18pt mark at x 504.8-532.2 beside it; ours set it full width
        // at p2's head and every line of p2 stood 32pt low.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.cell == nil, p.text.isEmpty, p.image == nil, p.inlineImages.isEmpty,
           style.sectionXML == nil, i > 0, let before = document.paragraphs[i - 1].cell, document.paragraphs[i - 1].keptTable == nil,
           let ts = document.tableStyles[before.table], ts.floatsOverText, !ts.pageAnchored, let kept = ts.keptPosition,
           kept.containsSubstring("w:vertAnchor=\"text\""), !kept.containsSubstring("w:horzAnchor=\"page\""),
           !kept.containsSubstring("w:tblpXSpec"), let widths = _columnWidths[before.table] {
            func twips(_ name: String) -> Double {
                guard let r = kept.rangeOfSubstring("\(name)=\"") else { return 0 }
                return Double(kept[r.upperBound...].prefix { $0 == "-" || $0.isNumber }) ?? 0
            }
            let size = style.mark?.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
            let strip = textWidth - _px(twips("w:tblpX") / 20) - widths.reduce(0, +) - _px(twips("w:rightFromText") / 20)
            // (Not before a narrow table that stands in the strip too: the mark keeps its line there, lo-5e49366b.)
            // (Nor where the table hangs a tblpY under its anchor: the marks keep their lines there and stand beside it, see
            // `_markBesideOffsetFloat`.)
            if strip >= _px(size), !_stripBesideLeftTable(before.table, i, document), ts.floatOffsetY == nil { _heights[i] = 0; _spaceBefore[i] = 0 }
        }
        // (The paragraph a centred float in a cell is anchored to takes no room: see `besideFloat`.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, style.besideFloat { _heights[i] = after; _spaceBefore[i] = 0 }
        // A floating frame takes no room either: the text that follows
        // starts where it does.
        if frameLeft != nil {
            _heights[i] = 0
            // (And stands as far above or below the text it is anchored
            // to as the frame says: a page number 11.75pt up.)
            if let frame = style.frame, frame.verticalAnchor == "text", frame.verticalAlign == nil { _spaceBefore[i] = before + push + _px(frame.y) }
        }
        // (A label in a text-anchored "notBeside" frame of no stated height, outside a
        // table, is drawn lower than the flow sets it by what the paragraph above's
        // space after and its own space before would have merged to: the two are added,
        // not collapsed, in the frame, and the text under it stays where it was. Lab
        // fhang, Word for Windows: label 3.0pt under the unframed twin's (6pt before
        // under 3pt after), the text below unmoved at 15, 20, 12pt and automatic lines
        // and whatever the picture in the line. Not in a table cell.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.cell == nil, i > 0, let frame = style.frame, frame.verticalAnchor == "text",
           let xml = style.frameXML, xml.containsSubstring("w:wrap=\"notBeside\""), !xml.containsSubstring("w:h=\""),
           document.paragraphs[i - 1].style.frameXML == nil, document.paragraphs[i - 1].cell == nil {
            let drop = min(_spacing(i - 1, document).after, _spacing(i, document).before)
            if drop > 0.01 {
                RuleTrace.hit("frame-label-adds-the-space-after-above-instead-of-merging")
                // (A table under the label goes down with it: lo-a197b7a8's "To confirm the health…"
                // (p21) and "To install the single server…" (p16) stand 3.1pt under where the
                // merged spacing put them in Word's print, the table's text with them, 18.6 under
                // the label as under a label that follows a table. A paragraph under it stays.)
                if i + 1 < document.paragraphs.count, document.paragraphs[i + 1].cell != nil {
                    _spaceBefore[i] += drop
                    _heights[i] += drop
                } else {
                    _inkShift[i] += drop
                }
            }
        }
        _topsValid = false
    }

    /// The width (points) of a paragraph that is a single `w:fitText` group, nil otherwise.
    @inline(never) static func _fitTextOverflow(_ p: RichParagraph) -> (groupPoints: Double, id: String)? {
        var found: (points: Double, id: String)? = nil
        for r in p.runs where r.length > 0 {
            guard let f = _fitText(r.style.keptXML), found == nil || found?.id == f.id else { return nil }
            found = f
        }
        guard let f = found else { return nil }
        return (f.points, f.id)
    }

    static func _picturesAndTabs(_ p: RichParagraph) -> Bool {
        // Opaque objects keep text-tab metrics: the legacy VML arrows
        // in zh-7773163d need that descent before the following boxes.
        !p.inlineImages.isEmpty && p.text.utf16.contains(0x09)
            && p.inlineImages.values.allSatisfy { !$0.data.isEmpty && $0.float == nil && $0.baseline == nil }
            && p.text.utf16.allSatisfy { $0 == 0xFFFC || $0 == 0x09 }
    }

    static func _textAlign(_ a: ParagraphAlignment) -> TextAlign {
        switch a {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .justify: return .justify
        }
    }
}

extension RichLayout {
    /// The style a first line stands on when it holds an unhinted em dash whose hAnsi face is East Asian over a Latin ascii face (ff493b's
    /// "Introduction \u{2014} ..." in Aptos Bold over a Malgun Gothic hAnsi): Word draws the dash in the hAnsi face, so the line takes that face's
    /// split ascent (Malgun Bold 1.088 em plus half the East Asian line's extra). The run's East Asian slot is set to the hAnsi family.
    static let _emDash: Character = "\u{2014}"
    @inline(never)
    func _eastDashLeadStyle(_ style: CharStyle, named: RichNamedStyle?) -> CharStyle? {
        guard let h = style.hAnsiFontFamily ?? named?.char.hAnsiFontFamily,
              theme.faceResolver?(h, false)?.isEastAsian == true else { return nil }
        if let latin = style.fontFamily ?? named?.char.fontFamily, latin == h, theme.faceResolver?(latin, false)?.isEastAsian == true { return nil }
        var out = style
        out.eastAsiaFontFamily = h
        RuleTrace.hit("word-em-dash-in-east-asian-hansi-face-stands-the-first-line-on-it")
        return out
    }

    /// The baseline rise of a first line that holds a Malgun-drawn symbol (①, ○, △, ·, ※, →, curly quotes) of a missing
    /// Korean face Word sets in Batang: the line's ascent is Malgun's 1.175 em against Batang's 1.009, times the spacing
    /// (c466d30a: the ① lines stood 3.4 pt high at 12 pt, 1.7 lines). The joiner of `_span` raises the line; the
    /// correction above had pulled the baseline back.
    @inline(never)
    /// Which lines of the paragraph hold a character Word draws in Malgun (the first-line rule's characters and faces).
    func _koreanSymbolLineFlags(_ p: RichParagraph, painter: TextPainter, lead: Int, named: RichNamedStyle?, document: RichDocument) -> [Bool] {
        let units = Array(p.text.utf16)
        var flags: [Bool] = []
        var from = 0
        while from < units.count {
            let end = max(from + 1, painter.getLineBoundary(TextPosition(offset: from + lead)).end - lead)
            var start = 0
            var found = false
            for run in p.runs where run.length > 0 {
                defer { start += run.length }
                let lo = max(start, from), hi = min(start + run.length, end, units.count)
                guard lo < hi, run.style.inlineImage == nil else { continue }
                let text = String(decoding: units[lo ..< hi], as: UTF16.self)
                let hit = text.unicodeScalars.contains { u in
                    let v = u.value
                    return v == 0x25CB || v == 0x25B3 || v == 0x25A1 || v == 0xB7 || (v >= 0x2460 && v <= 0x2469) || v == 0x203B || v == 0x2192
                        || v == 0x2018 || v == 0x2019 || v == 0x201C || v == 0x201D
                }
                guard hit else { continue }
                let viaEastAsia = theme.faceResolver?(run.style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                               ?? run.style.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.malgunSymbols == true
                let viaAscii = run.style.eastAsiaFontFamily == nil && run.style.fontFamily != nil
                    && theme.faceResolver?(run.style.fontFamily ?? "", true)?.malgunSymbols == true
                if !(run.style.eastAsiaFontFamily != nil && (run.style.fontHint ?? named?.char.fontHint) == "eastAsia"), viaEastAsia || viaAscii { found = true; break }
            }
            flags.append(found)
            from = end
        }
        return flags
    }

    func _koreanSymbolFirstLineRaise(_ p: RichParagraph, painter: TextPainter, lead: Int, named: RichNamedStyle?, document: RichDocument) -> Double? {
        let firstEnd = painter.getLineBoundary(TextPosition(offset: 0)).end - lead
        let units = Array(p.text.utf16)
        var start = 0
        var best: Double?
        for run in p.runs where run.length > 0 {
            defer { start += run.length }
            guard start < firstEnd else { break }
            let end = min(start + run.length, firstEnd, units.count)
            guard start < end, run.style.inlineImage == nil else { continue }
            let text = String(decoding: units[start ..< end], as: UTF16.self)
            let hit = text.unicodeScalars.contains { u in
                let v = u.value
                return (v >= 0x25A0 && v <= 0x25FF) || v == 0xB7 || (v >= 0x2460 && v <= 0x2469) || v == 0x203B || v == 0x2192
                    || v == 0x2018 || v == 0x2019 || v == 0x201C || v == 0x201D || v == 0xB1
            }
            let viaEastAsia = theme.faceResolver?(run.style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                           ?? run.style.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.malgunSymbols == true
            // (A quote or plus-minus sign that is a run of its own, set in Gulim, is drawn in Malgun Gothic: see `_span`'s joiner. xd b6f6c7d4 page 28.)
            let viaLone = run.style.loneQuote && !run.style.hAnsiNamedAsAscii
                && ["굴림", "gulim"].contains((run.style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? run.style.fontFamily ?? "").trimmingWhitespace().lowercased())
                && ["맑은 고딕", "malgun gothic"].contains((_normalChar(document)?.hAnsiFontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased())
            // (A run that names only a missing ascii face, with no eastAsia slot of its own, is judged by that face as in `_span`'s
            // joiner, though the style's eastAsia face is Batang itself: fe41a48c's 한양신명조 △△△ in 바탕글.)
            let viaAscii = run.style.eastAsiaFontFamily == nil && run.style.fontFamily != nil
                && (theme.faceResolver?(run.style.fontFamily ?? "", true)?.malgunSymbols == true || (run.style.fontFamily?.trimmingWhitespace() == "굴림" && text.unicodeScalars.contains { $0.value >= 0x25A0 && $0.value <= 0x25FF }))
            // (The won sign of a Korean Latin face with no ₩ of its own is Malgun's too: see `_span`'s joiner.)
            let won = text.unicodeScalars.contains { $0.value == 0x20A9 } && run.style.fontHint != "eastAsia"
                && theme.faceResolver?(run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false)?.isEastAsian == true
            guard (hit || won), !(run.style.eastAsiaFontFamily != nil && (run.style.fontHint ?? named?.char.fontHint) == "eastAsia"),
                  viaEastAsia || viaAscii || viaLone || won else { continue }
            let size = run.style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
            // (Word's shift is a constant 0.2833 em once the spacing is over single:
            // the same 3.4pt at 12pt for 1.7x (lab c466d30a) and 3x (xd 07eecf7a);
            // at single it stays 0.166 em.)
            // (Malgun's 1.288 em box above the baseline less the paragraph face's 1.006 em at the line's largest size: the same 0.2833 em
            // when the symbol is the largest run; a 11 pt quote beside 12 pt text rises only 2.1 pt, as Word's b6f6c7d4 page 5.)
            var tallest = size
            do {
                var s2 = 0
                for r2 in p.runs where r2.length > 0 {
                    defer { s2 += r2.length }
                    guard s2 < firstEnd else { break }
                    tallest = max(tallest, r2.style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize)
                }
            }
            let rise = 1.288 * size - 1.006 * tallest
            if rise > (best ?? 0) {
                RuleTrace.hit("word-korean-symbol-first-line-stands-on-malgun-ascent")
                best = rise
            }
        }
        return best
    }
}

extension RichLayout {
    /// Does a Shonar Bangla first line hold a Latin-drawn character? Letters and digits are Latin. A neutral ASCII mark (punctuation, space, underscore) takes the
    /// script of the strong characters in its OWN run: inside a run with Bengali it is drawn in Shonar (a comma in 3f7da49c's bullets), and a run of neutrals alone
    /// uses its ascii face (": ____" in an Arial run, 80152175). The rule is Word's; it replaced a code-point cutoff.
    @inline(never)
    func _shonarFirstLineHasLatin(_ p: RichParagraph, units: [UInt16], firstEnd: Int, named: RichNamedStyle?, document: RichDocument) -> Bool {
        var start = 0
        for run in p.runs where run.length > 0 {
            defer { start += run.length }
            guard start < firstEnd else { break }
            let end = min(start + run.length, firstEnd, units.count)
            guard start < end, run.style.inlineImage == nil else { continue }
            let slice = units[start ..< end]
            if slice.contains(where: { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) }) { return true }
            // (A space between Bengali words takes their script whatever its run's face: 80152175's Arial space run does not lift line 1.)
            guard slice.contains(where: { $0 > 0x20 && $0 <= 0x7E }) else { continue }
            if String(decoding: slice, as: UTF16.self).unicodeScalars.contains(where: { Self._indic.contains($0.value) }) { continue }
            let face = (run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
            if Self._bengaliMissingFace(face, document) != "shonar bangla" { return true }
        }
        return false
    }
}

extension RichLayout {
    /// The baseline a first line of Indic letters stands at when its face's ascent is above `target`.
        /// A first line with a character Word draws in Mangal for Noto Sans Tamil text (see `_markInMangal`, `_latinInNotoTamil`).
    @inline(never)
    func _firstLineHoldsMangalMark(_ p: RichParagraph, painter: TextPainter, lead: Int, named: RichNamedStyle?, document: RichDocument) -> Bool {
        let firstEnd = painter.getLineBoundary(TextPosition(offset: 0)).end - lead
        let units = Array(p.text.utf16)
        var start = 0
        for run in p.runs where run.length > 0 {
            defer { start += run.length }
            guard start < firstEnd else { break }
            let end = min(start + run.length, firstEnd, units.count)
            guard start < end, run.style.inlineImage == nil else { continue }
            let text = String(decoding: units[start ..< end], as: UTF16.self)
            let isMark: (Unicode.Scalar) -> Bool = { !Self._isIndic($0.value) && $0.value > 0x20 && $0.value != 0xA0 && $0.value != 0x200B && $0.value != 0x200C && $0.value != 0x200D && $0.value != 0x2060 && $0.value != 0xFFFC }
            guard text.unicodeScalars.contains(where: isMark) else { continue }
            if Self._latinInNotoTamil(run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? ""),
               !text.unicodeScalars.contains(where: { Self._isIndic($0.value) }) { return true }
            if Self._markInMangal(run.style.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "", p.text[...]) { return true }
        }
        return false
    }

    @inline(never)
    func _indicFirstLineAscent(_ p: RichParagraph, painter: TextPainter, lead: Int, named: RichNamedStyle?, document: RichDocument, target: Double,
                                style: RichParagraphStyle, pitch: Double?, lift: inout Double) -> Double? {
        var target = target
        var raisedTo: Double?
        var latinFloor = 0.0
        var markerFloor = false
        var kokilaOwn = 0.0
        var kokilaLine = 0.0
                    let firstEnd = painter.getLineBoundary(TextPosition(offset: 0)).end - lead
                    let units = Array(p.text.utf16)
                    var start = 0
                    // (A list's marker in a Latin face of its own (Symbol, a bullet) stands the first line on that face's ascent as a Latin run does:
                    // xd d760f1e5's "•" headings, Symbol 14 pt bold in a Kokila paragraph at 1.5 lines, 3.8 pt lower in Word's print.)
                    if p.style.list != nil, let face = _levelNumberFonts(p, document).latin?.trimmingWhitespace().lowercased(), face != "kokila",
                       var marker = p.runs.first(where: { $0.length > 0 })?.style {
                        marker.fontFamily = _levelNumberFonts(p, document).latin
                        if let size = _levelNumberSize(p, document) { marker.fontSize = size }
                        if let b = theme.baseline(for: marker, in: style, named: named, eastAsian: false, gridPitch: pitch, centresInLine: document.spacesForUnderline) {
                            RuleTrace.hit("word-list-marker-face-raises-the-first-line")
                            latinFloor = max(latinFloor, b); markerFloor = true
                        }
                    }
                    for run in p.runs where run.length > 0 {
                        defer { start += run.length }
                        guard start < firstEnd else { break }
                        let end = min(start + run.length, firstEnd, units.count)
                        guard start < end, run.style.inlineImage == nil else { continue }
                        let text = String(decoding: units[start ..< end], as: UTF16.self)
                        guard text.unicodeScalars.contains(where: { Self._isIndic($0.value) }) else {
                            // (A Latin run of Arial Unicode MS with no w:cs flag in a Devanagari paragraph is drawn in Yu Gothic, which stands the first line on its own
                            // 1.18 em ascent: lab aumsy2, Word's step into such a line 12.8 pt against 12.0 for a Nirmala one; fb94294e.)
                            if document.readFromFile, document.fontCharsets["arial unicode ms"] == "80",
                               text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x7F }),
                               (run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms",
                               !(run.style.keptXML?.containsSubstring("<w:cs/>") ?? false), !(run.style.keptXML?.containsSubstring("<w:cs ") ?? false),
                               p.text.unicodeScalars.contains(where: { $0.value >= 0x900 && $0.value < 0xB00 }) {
                                let size = run.style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                                if size * Self._yuGothicLine.0 > target + 0.01 {
                                    RuleTrace.hit("word-yu-gothic-latin-run-stands-the-first-line-on-its-ascent")
                                    target = size * Self._yuGothicLine.0
                                    raisedTo = target
                                }
                            }
                            // (A run of Latin letters on a Kokila line stands the line on its own face's baseline where that is the taller: dx2 cbb7ae39's
                            // "IRB" and "SS", Times New Roman 10 pt beside 10 pt Kokila, lab cb7: 9.3 pt above the baseline in Word's print, Kokila's 7.3.)
                            if text.unicodeScalars.contains(where: { ($0.value | 0x20) >= 0x61 && ($0.value | 0x20) <= 0x7A }),
                               (run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() != "kokila",
                               let b = theme.baseline(for: run.style, in: style, named: named, eastAsian: false, gridPitch: pitch, centresInLine: document.spacesForUnderline) { latinFloor = max(latinFloor, b) }
                            continue
                        }
                        var cs = (run.style.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
                        switch cs {
                        case "kalimati": cs = "mangal"
                        case "mangal", "kokila", "aparajita", "raavi", "shruti", "gautami", "vrinda", "utsaah", "shonar bangla": break
                        default: cs = text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value < 0xA00 }) ? Self._bengaliMissingFace(cs, document) : "nirmala ui"
                        }
                        // (Shonar Bangla Bold is its own face: 1721+978 of 2048; a first line of Bengali alone stands on its ascent, 15.1 pt at 18 pt, not on the stand-in's 0.96 em: dx2 3f7da49c's title, Word's baseline 60.1.)
                        let shonarBold = cs == "shonar bangla" && (run.style.bold || ((named?.char.bold ?? false) && !run.style.off.contains(.bold)))
                        guard let metrics = Self._indicLines[shonarBold ? "shonar bangla bold" : cs] else { continue }
                        let size = run.style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                        // (Utsaah with Utsaah as its Latin face too: the first line stands on Utsaah's 0.741 em, LOWER than the Latin
                        // stand-in's 0.95; lab utsaah1, Word's baseline 11.9 pt under the margin at 16 pt, ours 15.4.)
                        // (A Kokila line with no Latin letter on it stands on Kokila's ascent whatever the paragraph's Latin face: dx2 cbb7ae39's
                        // header and heading, Calibri as the Latin face, 10 and 12 pt Hindi alone on the line, 2 pt higher in Word's print.)
                        let noLatin = (cs == "kokila" || cs == "shonar bangla") && !(cs == "shonar bangla"
                            ? _shonarFirstLineHasLatin(p, units: units, firstEnd: firstEnd, named: named, document: document)
                            : units[0 ..< min(firstEnd, units.count)].contains(where: { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) }))
                        if cs == "utsaah" || cs == "kokila" || (cs == "shonar bangla" && noLatin), noLatin || (run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == cs,
                           abs(size * metrics.0 - target) > 0.01,
                           // (An at-least line taller than the face keeps its old place: 6c7504e9 heading, 24 pt at least over a 16 pt face. A multiple puts its extra under the line, so the baseline stays on the face's ascent: lab mmatrix2.)
                           !(cs == "kokila" && ((p.style.lineHeightPoints ?? 0) > size * (metrics.0 + metrics.1) + 0.01)) {
                            RuleTrace.hit("word-utsaah-first-line-stands-on-utsaah-ascent")
                            target = size * metrics.0
                            raisedTo = target
                            kokilaOwn = target
                            kokilaLine = size * (metrics.0 + metrics.1)
                        } else if size * metrics.0 > target + 0.01, !(cs == "nirmala ui" && (style.lineHeightPoints == nil || style.lineHeightIsMinimum)
                                  && _isSolaimanLipi(run.style, named, document)
                                  && units[0 ..< min(firstEnd, units.count)].contains(where: { $0 >= 0x20 && $0 < 0x7F })) {
                            RuleTrace.hit("word-indic-first-line-stands-on-its-face-ascent")
                            target = size * metrics.0
                            raisedTo = target
                        } else if cs == "nirmala ui", style.lineHeightPoints == nil || style.lineHeightIsMinimum, let mangal = Self._indicLines["mangal"],
                                  _isSolaimanLipi(run.style, named, document),
                                  units[0 ..< min(firstEnd, units.count)].contains(where: { $0 >= 0x20 && $0 < 0x7F }) {
                            // (A first line holding a space or ASCII mark in a missing Bengali face (SolaimanLipi) is Mangal's own line, Word draws those in Mangal:
                            // the baseline stands on Mangal's ascent, 14.9 pt at 12 pt, not on the Latin face's; under an "at least" height the extra goes above
                            // the baseline only where Mangal's falls short of the minimum. xd 73caaeda's authors line, 13.5 pt at least 22.5: Word's step into it
                            // 21.4, ours 23.5; its body's first line 20.8 under the rule of dashes, ours 18.9.)
                            let stand = style.lineHeightPoints.map { max(size * mangal.0, $0 - size * mangal.1) } ?? size * mangal.0
                            if abs(stand - target) > 0.01 {
                                RuleTrace.hit("word-solaimanlipi-first-line-stands-on-mangal-ascent")
                                target = stand
                                raisedTo = target
                            }
                        } else if cs == "nirmala ui", size * metrics.0 < target - 0.01, _nikoshLettersOnlyLine(units, firstEnd, run, named, document) {
                            // (A line of Bengali letters and spaces in Nikosh, a face Windows lacks: Word draws the letters in Nirmala UI
                            // and stands the line on Nirmala's ascent, 1.079 em, not on Mangal's 1.241 that the paragraph's Latin face
                            // gives the strut. dx2 bede0fbc's header lines and its "রিটার্ন রেজিস্টারের" rows: 2 pt (12 pt text) and
                            // 1.6 pt (11 pt) higher in Word's print, a line with a bracket (Mangal) where ours was right.)
                            RuleTrace.hit("word-nikosh-letters-line-stands-on-nirmala-ascent")
                            target = size * metrics.0
                            raisedTo = target
                        }
                    }
                    if kokilaOwn > 0, latinFloor > kokilaOwn + 0.01 {
                        // (Less what the engine's own first line already stands above Kokila's ascent: a paragraph whose strut is not forced grows the line itself.)
                        let given = max(0, (painter.computeLineMetrics().first.map { $0.baseline / max(0.0001, _px(1)) } ?? kokilaOwn) - kokilaOwn)
                        // (A marker face of its own: the engine's own taller strut already grows the line by its multiple of the difference; only the rest is lifted.)
                        let engineGrowth = markerFloor ? max(0, painter.height / max(0.0001, _px(1)) - Double(max(1, painter.computeLineMetrics().count)) * kokilaLine * max(1, style.lineSpacing)) : given
                        let more = latinFloor - kokilaOwn - engineGrowth
                        if more > 0.01 { lift = max(lift, more) }
                        raisedTo = latinFloor
                    }
                        return raisedTo
    }
}


extension RichLayout {
    /// A top-and-bottom or square/tight-wrapped picture more than 2pt above the empty first paragraph of the document that holds it
    /// (dx2 en 61ec937a: a square-wrapped logo 40pt above stands at the margin, 72.0 in Word's print, and the text wraps beside it).
    @inline(never)
    func _atPageTopNegativeOffset(_ i: Int, _ image: ImageAttachment) -> Bool {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, let f = image.float, (f.bandsPage || (f.wraps && !f.wrapsTight && image.textBox == nil && image.sourceXML?.containsSubstring("txbxContent") != true)), f.verticalAlign == nil,
              f.verticalFrom == "paragraph", f.y < -2, i == 0, !floatsFrames, regionTopOnPage == nil else { return false }
        // (One lying wholly above its paragraph is not lifted: sa1 8e800da4's 28pt picture 50.4pt up stands 57.6pt from its paragraph's top in Word's print, ours at the paragraph's.)
        if f.y + image.height + f.effectBottom <= 0 { return false }
        return true
    }
}

extension RichLayout {
    /// The first line holds only Indic letters, spaces and joiners, and the run's Latin face is Nikosh.
    @inline(never)
    func _nikoshLettersOnlyLine(_ units: [UInt16], _ firstEnd: Int, _ run: Run, _ named: RichNamedStyle?, _ document: RichDocument) -> Bool {
        let latin = (run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
        // (Siyam Rupali, Windows lacks it too and Word draws its Bengali letters in Nirmala UI: lab e86-pitch, every Bengali-only page's first
        // baseline 2.1 pt higher in Word's print than ours, which stood it on Malgun Gothic's ascent, the face its Latin falls to.)
        guard latin == "nikosh" || latin == "siyam rupali" else { return false }
        for u in units[0 ..< min(firstEnd, units.count)] {
            if u == 0x20 || u == 0x200B || u == 0x200C || u == 0x200D || u == 0x2060 || u == 0xA0 { continue }
            if Self._isIndic(UInt32(u)), u != 0x964, u != 0x965 { continue }
            return false
        }
        return true
    }
    /// For each line of `painter`, whether the word that starts it is no wider than `room`: the test for a left piece beside a box (a
    /// word of ideographs is one character).
    @inline(never)
    static func _nextWordFits(_ painter: TextPainter, _ span: InlineSpan, room: Double) -> [Bool] {
        let units = Array(span.toPlainText(includeSemanticsLabels: false, includePlaceholders: true).utf16)
        var out: [Bool] = []
        var at = 0
        while at < units.count {
            let r = painter.getLineBoundary(TextPosition(offset: at))
            let s = max(r.start, at)
            var e = s
            if e < units.count, units[e] >= 0x2E80 { e += 1 } else {
                while e < units.count, units[e] != 0x20, units[e] != 0x0A, units[e] != 0x200B, units[e] != 0x2D, !(units[e] >= 0x2E80) { e += 1 }
                if e < units.count, units[e] == 0x2D { e += 1 }
            }
            var w = 0.0
            if e > s { for b in painter.getBoxesForSelection(TextSelection(baseOffset: s, extentOffset: e)) { w += b.right - b.left } }
            out.append(w <= room + 0.01)
            guard r.end > at || r.end > r.start else { break }
            at = max(r.end, at + 1)
        }
        return out
    }

}

extension RichLayout {
    /// The unscaled first-line baseline of the text and the excess of a list number's face over it (points), for a number in a taller face at its own size.
    func _labelFaceGrowth(_ p: RichParagraph, named: RichNamedStyle?, document: RichDocument, style: RichParagraphStyle) -> (target: Double, growth: Double)? {
        guard !p.runs.isEmpty, let firstRun = p.runs.first(where: { $0.length > 0 }),
              let xml = p.style.listId.flatMap({ document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.numberRPrXML }),
              let r = xml.rangeOfSubstring("w:ascii=\"") else { return nil }
        let family = String(xml[r.upperBound...].prefix { $0 != "\"" })
        let textFace = firstRun.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily
        let size = firstRun.style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
        let numberSize = _levelNumberSize(p, document) ?? size
        guard !family.isEmpty, numberSize <= size + 0.01,
              let nb = theme.faceResolver?(family, false)?.baseline, let tb = theme.faceResolver?(textFace, false)?.baseline,
              nb * numberSize - tb * size > 0.02,
              let target = theme.baseline(for: firstRun.style, in: style, named: named, eastAsian: false, gridPitch: nil, centresInLine: document.spacesForUnderline) else { return nil }
        return (target, nb * numberSize - tb * size)
    }
}
