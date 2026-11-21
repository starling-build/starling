// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paragraph+Body7": step 7 of `_layoutParagraphBody`.
// A pure move, scripted (test/tools/split-paragraph.py): the bodies are as they were; the function's locals are the fields of `_ParaFrame`.

import Flutter
import FlutterSwiftBridge
import Foundation

extension _ParaFrame {
    func c7() -> Void {
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
        combined = inline.contains { $0.image?.name == "combine" } && painter.computeLineMetrics().count == 1
        // (Not a table nested in a cell: a block, not a line.)
        inLine = p.image.map { $0.float == nil && $0.textBox?.growsToFit != true }
            ?? ((p.inlineImages.values.contains { $0.float == nil && $0.baseline == nil } || combined) && painter.computeLineMetrics().count == 1)
        _blk9()
        // (A paragraph that ends in a line break ends with a line of its
        // mark alone, as tall as the mark's own line: zh-17749c13's
        // paragraph of one bold 仿宋_GB2312 break (YaHei to Word, two
        // 15.6pt pitches) under a 12pt 宋体 mark is three pitches in
        // Word's print — the break's two and the mark's one — where the
        // grid's strut set both lines two, and its page ran a pitch long.)
        if (theme.wordRules || (theme.officeLatinBreaks && style.mark != nil)), p.text.unicodeScalars.last == "\n" || p.text.unicodeScalars.last == "\u{2028}",
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
               let m = RichLayout._indicLines["mangal"],
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
        total = before + push + bodyHeight + after
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
                   float.wrapSide == nil, !image.data.isEmpty || RichLayout.drawsObject?(image) == true {
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
        onlyFloats = p.image.map(clear)
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
}
