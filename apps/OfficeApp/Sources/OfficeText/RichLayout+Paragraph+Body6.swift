// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paragraph+Body6": step 6 of `_layoutParagraphBody`.
// A pure move, scripted (test/tools/split-paragraph.py): the bodies are as they were; the function's locals are the fields of `_ParaFrame`.

import Flutter
import FlutterSwiftBridge
import Foundation

extension _ParaFrame {
    func c6() -> Void {
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
                      image.height > 0, float.wrapSide == nil, !image.data.isEmpty || RichLayout.drawsObject?(image) == true else { continue }
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
        bodyHeight = painter.height + _px(segoeLift) - w2Trim
        if let pair = RichLayout._paired(painter) { bodyHeight -= pair.saving }
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
        spacesOnly = theme.wordRules && p.style.pageBreakInline && p.image == nil && p.text.unicodeScalars.contains(" ")
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
    }
}
