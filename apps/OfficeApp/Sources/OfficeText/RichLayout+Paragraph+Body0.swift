// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paragraph+Body0": step 0 of `_layoutParagraphBody`.
// A pure move, scripted (test/tools/split-paragraph.py): the bodies are as they were; the function's locals are the fields of `_ParaFrame`.

import Flutter
import FlutterSwiftBridge
import Foundation

extension _ParaFrame {
    func c0() -> Void {
        _heldTallerLatin.remove(i)
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
        style = p.style
        wordList = _wordList(p, document)
        sides = _sideIndents(p, at: i, document)
        // `w:mirrorIndents` on a page Word mirrors: the right indent is
        // the left one and the first line's, the left the right one and
        // a hanging indent's depth (measured: `office.md`).
        // (A list paragraph's text edge is its level's, `_wordList`, and is
        // mirrored the same way: zh-bdae17c0's "․" list, left 1162 hanging
        // 425 and right 108, sets its lines 26.65pt in and ends them 36.85
        // short of the margin on its even pages in Word for Windows' print,
        // where ours kept the level's 58.1 and lost the right indent.)
        listLeft = wordList?.left
        if _mirrored.contains(i) {
            if let wl = wordList {
                listLeft = sides.right + max(0, -wl.first)
                sides = (left: sides.left, right: wl.left + wl.first)
            } else {
                let first = firstLineIndent(p, at: i, document)
                sides = (left: sides.right + max(0, -first), right: sides.left + first)
            }
        }
        ownLeft = listLeft.map { _px($0) } ?? _px(sides.left)
        left = wordList != nil ? ownLeft
            : ownLeft + (style.list != nil ? _px(_listIndents(p, document)?.left ?? theme.listIndent * Double(style.listLevel + 1)) : 0)
        right = _px(sides.right)
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
        width = _flowWidth(i)
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
        gridCut = 0.0   // what the cells' floor took off the width
        _q0()
        // A floating frame: as wide as it says, from where it says.
        frameLeft = nil
        _q1()
        // (A frame on the page in the body is as wide as it says: the
        // 482pt title frame of zh-90e0cea8's cover holds its 18-character
        // title on one line, where the 420pt column parted it.)
        // (A frame set in the text, with no text beside it, is as wide as it
        // says, centred on the page where it says that: tdf105035_framePrB's
        // IEEE title, w 9360 over the style's page anchor and xAlign
        // centre, is 468pt wide and parts "…TRANSACTIONS | and JOURNALS" in
        // Word's print, where ours set it across the 518pt column.)
        notBesideInText = style.frame?.verticalAnchor == "text" && (style.frameXML ?? "").containsSubstring("w:wrap=\"notBeside\"")
        if frameLeft == nil, theme.wordRules, p.cell == nil, let frame = style.frame, let w = frame.width,
           RichLayout._framePlaced(frame), RichLayout._onThePage(style) || notBesideInText {
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
            if notBesideInText || RichLayout._stripFrame(style), frame.horizontalAnchor == "page", frame.horizontalAlign == "center",
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
        textWidth = max(1, width - left - right + (frameLeft ?? 0))
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
        _blk0()
        // The box before the text: the first line's indent, or — for a
        // list as Word sets it — from the number at the first line's
        // offset to where the text starts: at the number's end, a space
        // after it, or the next tab stop (the text's own left, when the
        // number fits in the hanging indent).
        lead = _px(firstLineIndent(p, at: i, document))
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
        _blk2()
        _leadWidth[i] = lead
        // Tabs, as Word sets them: each takes the text to the next stop —
        // the paragraph's own, the hanging indent, then the document's
        // default distance apart — and a centred, right or decimal stop
        // sets what follows about it. The engine gives a tab no width of
        // its own, so each is widened by what its stop needs.
        tabs = [:]
        // What stands past the margin after a right stop at it (or set
        // there), by the offset of its last character: drawn there,
        // taking no room.
        hangs = [:]
        // The tabs to a right stop at the margin (or set there): what
        // follows one that starts inside it may run past the margin, and
        // the line fitting is told so.
        runsPast = []
        clampedStops = []
        // A right stop honoured past the margin: how far past (tab offset -> points in px).
        beyond = [:]
        pictureTabs = RichLayout._picturesAndTabs(p)
        atMargin = []
        leftTabs = []    // tabs that take a first line's label to its hanging indent
        lonePastTabs = []  // a lone tab whose default stop is past the margin: held, goes down
        beforeTabs = []  // spaces a justified line does not stretch: before its last tab
        _leaders[i] = []
        // (PowerPoint's the same way: its stops from the text's left, the
        // hanging indent first, then `defTabSz` apart — HowWeRefactor's
        // quotes, their first line at the indent and "– Martin Fowler" at
        // the seventh inch, PowerPoint's print to a tenth of a point.)
        // (The lines' own insets beside a float, once they are known: a tab is measured from the margin, so a line the float
        // holds in starts its tabs that far along, and a stop past the window's far edge is Word's, not the column's.)
        tabWindows = []
        forcedWraps = []
        afterTabWraps = []
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
        leadTab = false
    }
}
