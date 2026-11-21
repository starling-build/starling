// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paragraph+Body2": step 2 of `_layoutParagraphBody`.
// A pure move, scripted (test/tools/split-paragraph.py): the bodies are as they were; the function's locals are the fields of `_ParaFrame`.

import Flutter
import FlutterSwiftBridge
import Foundation

extension _ParaFrame {
    func c2() -> Void {
        // The engine's justifying sets every space of a line to the one
        // step it puts between ideographs, and the two spaces after
        // "第一条" are gone. In a justified paragraph the spaces beside
        // East Asian text are therefore set again as no-break spaces —
        // characters like any other, which keep their width — but only
        // those inside a line, and only if every line then breaks
        // where it did: a no-break space at a line's end would count
        // against the line, and a plain one takes no room there.
        held = tabsHeld
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
           p.runs.contains(where: { RichLayout._fitText($0.style.keptXML) != nil }), painter.computeLineMetrics().count > 1 {
            var grouped = Set<Int>()
            var at = 0
            for r in p.runs {
                if r.length > 0, RichLayout._fitText(r.style.keptXML) != nil { for o in at ..< (at + r.length) { grouped.insert(o) } }
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
        // Slides: PowerPoint justifies a line of East Asian text by sharing its spare room evenly over every gap between its
        // characters (befe9f6b p6: 24.7 pt a gap on a 24 pt line); the engine's justify puts it only at script boundaries.
        if !theme.wordRules, style.alignment == .justify, !style.rightToLeft, textWidth < 50_000, !p.text.isEmpty,
           (p.cell?.textDirection ?? .horizontal) == .horizontal, painter.computeLineMetrics().count > 1 || _lastLineHangsMark(p, fit),
           p.text.unicodeScalars.contains(where: { RichLayout._isEastAsianScalar($0.value) }) {
            let units = Array(p.text.utf16)
            let map = _OffsetMap(lead: _lead(i), inserts: _inserts[i])
            let starts = _lineStarts(painter, map, count: units.count)
            let kept = align, keptLift = numberLift
            align = .left
            let flat = laidOut(_span(for: p, at: i, document, textWidth: textWidth, lead: lead, adjust: fit.isEmpty ? tabs : fit, held: held).0)
            align = kept
            numberLift = keptLift
            func ea(_ k: Int) -> Bool { RichLayout._isEastAsianScalar(UInt32(units[k])) }
            var spread: [Int: Double] = [:]
            var markFit: [Int: Double] = [:]
            // (The paragraph's last line is not justified, unless its closing mark hangs past the margin: PowerPoint then spreads the
            // line until the mark stands at the edge, befe9f6b p6 "…重要。".)
            let hangLast = _lastLineHangsMark(p, fit)
            for (k, start) in starts.enumerated() where k + 1 < starts.count || hangLast {
                var end = min(k + 1 < starts.count ? starts[k + 1] : units.count, units.count)
                guard start >= 0, start < units.count else { continue }
                while end > start, [0x20, 0x09, 0x0A, 0x0B, 0x3000].contains(units[end - 1]) { end -= 1 }
                guard end > start + 1 else { continue }
                let gapsAt = ((start + 1) ..< end).filter { !(units[$0] >= 0xDC00 && units[$0] <= 0xDFFF) && (ea($0) || ea($0 - 1)) }
                guard !gapsAt.isEmpty, end > start else { continue }
                let boxes = flat.getBoxesForSelection(TextSelection(baseOffset: map.painter(start), extentOffset: map.painter(end)))
                guard var right = boxes.map({ $0.right }).max() else { continue }
                if k + 1 >= starts.count {
                    // (The last line: only where its closing mark hangs, i.e. has no room of its own; the text before it is spread so the
                    // mark's origin lands on the edge.)
                    let markBoxes = flat.getBoxesForSelection(TextSelection(baseOffset: map.painter(end - 1), extentOffset: map.painter(end)))
                    guard markBoxes.isEmpty || (markBoxes.last?.right ?? 0) > textWidth - _px(1) else { continue }
                    let before = flat.getBoxesForSelection(TextSelection(baseOffset: map.painter(start), extentOffset: map.painter(end - 1)))
                    guard let b = before.map({ $0.right }).max() else { continue }
                    // (The mark is set a sliver wide so it stands at the edge without wrapping.)
                    let natural = (markBoxes.last.map { $0.right - $0.left } ?? 0) - (fit[end - 1] ?? 0)
                    guard natural > _px(0.5) else { continue }
                    markFit[end - 1] = -(natural - _px(0.5))
                    right = b + _px(0.5)
                }
                let spare = textWidth - right - _px(0.05)
                guard spare > 0 else { continue }
                for g in gapsAt { spread[g] = spare / Double(gapsAt.count) }
            }
            flat.dispose()
            if !spread.isEmpty {
                let (span, _, inserts) = _span(for: p, at: i, document, textWidth: textWidth, lead: lead, adjust: (fit.isEmpty ? tabs : fit).merging(markFit) { $1 }, held: held, spread: spread)
                let again = laidOut(span)
                if _lineStarts(again, _OffsetMap(lead: _lead(i), inserts: inserts), count: units.count) == starts {
                    painter.dispose()
                    painter = again
                    _inserts[i] = inserts
                } else {
                    again.dispose()
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
        bareBreak = _emptyBreakFragment(i, document)
        bTop = bareBreak || _bordersJoin(i - 1, i, document) ? 0 : style.borders?.top.map { _px($0.space + RichLayout._ruleRoom($0.style, $0.width)) } ?? 0
        bBottom = bareBreak || _bordersJoin(i, i + 1, document) ? 0 : style.borders?.bottom.map { _px($0.space + RichLayout._ruleRoom($0.style, $0.width)) } ?? 0
        spacing = _spacing(i, document)
        // (Exact under Word's rules, whose lines keep their fractions
        // too: 14pt is 18.67px on a screen, and a whole pixel more under
        // every web-spaced paragraph stood Word's 14pt gap at 14.75.)
        // (A text frame with no text beside it, over its vSpace, leaves the
        // text after it 2 x that and 2.7pt more below it: tdf105035_framePrB's
        // title and authors frames, vSpace 187 twips, put the authors line
        // 21.0pt and the abstract 21.8pt lower than ours, with a "notBeside"
        // frame's own spacing after counted. One witness's constant.)
        frameGap = 0.0
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
        cellBreakLead = theme.wordRules && RichTextTheme.wordWindowsPages && (document.compatibilityMode ?? 12) >= 15
            && style.cellBreakOpens && p.cell != nil && (i == 0 || document.paragraphs[i - 1].cell != p.cell)
        // (A document with `suppressTopSpacing` stands the first line of a page of exact
        // lines higher by 0.8 x (the height - 12pt), and the lines under it with it. Lab
        // stsp, Word for Windows: 9.6, 4.8, 14.4 and 19.2pt at 24, 18, 30 and 36pt
        // whatever the font size; nothing at 12pt or at an automatic height; a space
        // before stays. Here for the document's first paragraph and one that opens a page
        // by a break; lo orrick's body, 9.5pt high in Word's print.)
        topRaise = 0.0
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
        before = (theme.wordRules ? (cellBreakLead ? 0 : spacing.before) + bTop : (spacing.before + bTop).rounded()) + _px(frameGap) - topRaise + _sectionEndnotesHeight(before: i, document)
        after = spacing.after + bBottom
        // Where the engine put the baseline (a strut's even leading) is
        // not where Word has it: the text is drawn from as much lower.
        _inkShift[i] = 0
        _numberLiftShift[i] = 0
        segoeLift = 0.0   // what a Segoe UI Symbol shape adds over the first line (`RichTextTheme.segoeSymbolShapes`)
        // (A paragraph whose runs differ only by a raised or lowered one
        // has no strut, and its lines are each as tall as one of its own
        // text: its baseline wants the same correction — endnotes' "A
        // pendant worn…", its "i" mark among 11pt Calibri, stood 1.6pt
        // under Word's.)
        // (A paragraph with no strut whose first line holds a character the
        // face's chain sends to Yu Gothic or JhengHei has those faces' own
        // line height, and its text wants the same first-line correction:
        // lab cm236d's JP paragraph with 书/东 stood 1.85pt low.)
        chainFaceLine = {
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
                    guard let u = ch.unicodeScalars.first?.value, RichLayout._isEastAsianScalar(u), !covers.contains(u) else { continue }
                    let k = chain.firstIndex { $0.covers?.contains(u) ?? true } ?? chain.count - 1
                    if RichLayout._chainFaceLines[chain[k].family] != nil { return true }
                }
            }
            return false
        }()
    }
}
