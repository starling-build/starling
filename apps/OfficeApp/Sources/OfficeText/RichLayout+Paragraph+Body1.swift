// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paragraph+Body1": step 1 of `_layoutParagraphBody`.
// A pure move, scripted (test/tools/split-paragraph.py): the bodies are as they were; the function's locals are the fields of `_ParaFrame`.

import Flutter
import FlutterSwiftBridge
import Foundation

extension _ParaFrame {
    func c1() -> Void {
        if theme.markersAtHang || theme.wordRules, p.text.utf16.first == 0x09, let e = tabs[0], e != 0 {
            // (A leading tab that carries a right stop to the margin: the tab's own width and the text after it
            // add up to the line's width exactly, and a rounding error in the sum sent the page number to a second
            // line. lo/dx2 99cfc555's even header, "<tab>2", stop at the margin; Word sets it on one line.)
            lead += theme.wordRules && lead + e > textWidth * 0.9 ? e - 0.01 : e
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
        underHeld = []
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
                    let closed = end < units.count && Unicode.Scalar(units[end]).map { RichLayout._closingMarks.contains(Character($0)) } == true
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
        tabRuns = theme.wordRules && RichTextTheme.wordWindowsPages
            ? Set(tabs.keys.filter { t in (t > 0 && p.text.utf16[p.text.utf16.index(p.text.utf16.startIndex, offsetBy: t - 1)] == 0x09) || (t + 1 < p.text.utf16.count && p.text.utf16[p.text.utf16.index(p.text.utf16.startIndex, offsetBy: t + 1)] == 0x09) }).subtracting(atMargin)
            : []
        if !tabRuns.isEmpty { RuleTrace.hit("tab-runs-do-not-hang-past-the-margin") }
        tabsHeld = (theme.wordRules && style.alignment == .justify ? Set(tabs.keys).subtracting(atMargin) : []).union(leadTab && style.alignment == .justify ? [0] : []).union(underHeld).union(beforeTabs).union(tabRuns).union(lonePastTabs).union(afterTabWraps)
            .union(theme.wordRules && RichTextTheme.wordWindowsPages ? RichLayout._underlinedClosingCounted(p) : [])
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
        tieSlack = p.text.unicodeScalars.contains { $0.value >= 0x900 && $0.value <= 0x97F } && !p.text.unicodeScalars.contains { $0.value >= 0x2E80 } ? 0.12 : 0.001
        tieShort = (first: false, rest: false)
        _q3()
        // (Beside a float: the lines that stand level with it are held in too.
        // Laid out once as they fall, the lines the float reaches get an
        // indent each, and laid again until they settle.)
        besideLineIndents = []
        equationLinesGrowAfterLayout = false
        besideIndent = _besideLead[i]
        besideRight = besideIndent > 0 && _besideRightSide[i]
        besideBand = besideIndent > 0 ? _besideBand(i, document) : nil
        colWrapBoxes = _colWrap[i]
        if let boxes = colWrapBoxes, besideIndent == 0, !boxes.isEmpty { besideIndent = 1; besideBand = (-1, -1) }
        else
        if besideIndent > 0, besideBand == nil { _besidePending.insert(i) }
        else if besideIndent == 0, let own = _besideOwn(i, p, document) { besideIndent = own.indent; besideBand = own.band; besideRight = own.right; besideLeftRoom = own.leftRoom
            if colWrapBoxes == nil, besideLeftRoom == nil, !besideRight, let seq = _besideSeq[i] { colWrapBoxes = seq; besideIndent = 1; besideBand = (-1, -1); RuleTrace.hit("word-boxes-one-under-the-other-hold-lines-by-their-own-edge") } }
        else if besideIndent == 0, let own = _stripUse[i] { besideIndent = own.indent; besideBand = own.band; besideRight = own.right }
        if let cap = _bandCap[i], besideIndent > 0, besideLeftRoom == nil, let b = besideBand, b.bottom > cap { besideBand = (b.top, cap) }
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
        (span, inline, inserts) = _span(for: p, at: i, document, textWidth: textWidth, lead: lead,

                                            adjust: hangs.isEmpty ? tabs : tabs.merging(hangs) { $0 + $1 }, held: tabsHeld)
        _inserts[i] = inserts
        // A right-to-left paragraph runs from the right, and its "left"
        // (Word's start) is the right edge.
        align = RichLayout._textAlign(style.alignment)
        // (jc thaiDistribute, Word's print of lab thd1: a line broken at a space is set out to the full width by room between its
        // letters, the spaces taking the same share as a letter and none of their own; the engine's justify, which widens only
        // the spaces, is off for it — `_thaiDistribute` below spreads the lines.)
        // (Compatibility 15 files print it as plain justify: 10ffb69f, a3710694, c929c653, 75eee205 fell when spread, and the
        // files below 15, or naming none, rose: 46490205 50 to 55, e93587db 82 to 86, 93962bba 96 to 100.)
        thaiDistributed = theme.wordRules && RichTextTheme.wordWindowsPages && style.alignment == .justify
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
        picturesInLine = inline.contains { entry in
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
        spacedOver = theme.wordRules && style.lineHeightPoints == nil
            && (style.lineSpacing > 1.2 || document.usesEastAsianLayout)
        // (A Thai paragraph too, its bold's hair-taller line held with the regular (`_sameLine` wide): its stand-in is drawn at 0.82 of the
        // size and, with no strut, the faces stacked 2.5 pt over: dx2 3f86ce1b's "ข้อ 1." lines, 24.6 apart for Word's 22.0.)
        thaiNear = theme.wordRules && style.lineHeightPoints == nil && p.text.unicodeScalars.contains(where: { (0x0E01 ... 0x0E5B).contains($0.value) })
        // (A larger number's height over the first line, where the
        // paragraph keeps its strut: see `laidOut`.)
        numberLift = 0.0
        for item in inline { if let image = item.image { _ensureDecoded(image) } }
        _inline[i] = inline.compactMap(\.image)
        _inlineBoxes[i] = inline.indices.filter { inline[$0].image != nil }
        _floats[i] = p.image?.float
        _floatImages[i] = p.image?.float != nil ? p.image : nil
        painter = laidOut(span)
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
        fit = _fitEastAsianLines(p, at: i, document, textWidth: textWidth, first: painter, leadWidth: lead, tabs: tabs, leftTabs: leftTabs, runsPast: runsPast, beyond: beyond, tieShort: tieShort,
                                     lineIndents: besideLeftRoom != nil || _besideRightAt[i] != nil || (theme.wordRules && besideLineIndents.contains(where: { $0.right > 0 })) || _setup(ofParagraph: i).headerWrapLeft > 0 || !(colWrapBoxes?.isEmpty ?? true) ? besideLineIndents : [])
        if !fit.isEmpty {
            painter.dispose()
            painter = laidOut(_span(for: p, at: i, document, textWidth: textWidth, lead: lead, adjust: fit, held: tabsHeld).0)
        }
        // PowerPoint hangs a line-end 、 or 。 past the margin (its hangingPunct, on by default): where one would open the next line, it
        // is set no wider than a point, so the line takes it and the character before it (befe9f6b p6 "…明記する。").
        if _hangsLineEndMarks(p),
           p.text.utf16.contains(where: { $0 == 0x3001 || $0 == 0x3002 || $0 == 0xFF0C || $0 == 0xFF0E || $0 == 0x201D }) {
            let units = Array(p.text.utf16)
            func isMark(_ k: Int) -> Bool { k < units.count && (units[k] == 0x3001 || units[k] == 0x3002 || units[k] == 0xFF0C || units[k] == 0xFF0E || units[k] == 0x201D) }
            var stays = Set<Int>()
            for _ in 0 ..< 3 {
                let map = _map(i)
                let starts = _lineStarts(painter, map, count: units.count)
                var adj = fit
                for s0 in starts.dropFirst() where s0 > 0 {
                    // (The mark opens the line, or follows its one first character: that character comes up with it.)
                    let m = isMark(s0) ? s0 : (isMark(s0 + 1) ? s0 + 1 : (s0 + 2 < units.count && units[s0 + 1] == 0x20 && units[s0 + 2] == 0x201D ? s0 + 2 : -1))
                    guard m >= 0, adj[m] == nil, !stays.contains(m) else { continue }
                    let boxes = painter.getBoxesForSelection(TextSelection(baseOffset: map.painter(m), extentOffset: map.painter(m) + 1))
                    if let b = boxes.first { adj[m] = -max(0, b.right - b.left - _px(0.5)) }
                }
                if adj.count == fit.count { break }
                let trial = laidOut(_span(for: p, at: i, document, textWidth: textWidth, lead: lead, adjust: adj, held: tabsHeld).0)
                let after = _lineStarts(trial, map, count: units.count)
                if after == starts { trial.dispose(); break }
                // (A mark set narrow stands at its line's end. Where the line took more and it no longer does, it keeps its width, and
                // the paragraph is laid out again as it was: 44a22c19 p15 "…読む。（異なる…" breaks after the 。 in the print.)
                let loose = adj.keys.filter { fit[$0] == nil && $0 + 1 < units.count && !after.contains($0 + 1) }
                if !loose.isEmpty {
                    trial.dispose()
                    stays.formUnion(loose)
                    continue
                }
                painter.dispose(); painter = trial; fit = adj
            }
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
    }
}
