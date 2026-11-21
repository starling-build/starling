// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paragraph+Body5": step 5 of `_layoutParagraphBody`.
// A pure move, scripted (test/tools/split-paragraph.py): the bodies are as they were; the function's locals are the fields of `_ParaFrame`.

import Flutter
import FlutterSwiftBridge
import Foundation

extension _ParaFrame {
    func c5() -> Void {
        // (A line that holds text its run raises or lowers (`w:position`), in a paragraph of single spacing: Word makes the line as
        // tall as the text's top plus the raise, and as deep as its foot plus the lowering. Lab CP3 (xb docx-8f1703b9, 11pt Calibri,
        // "raised" at 6pt, "lowered" at -6pt): pitches 19.44 into the raised line (13.44 + 6, above its baseline), 13.44 out of it,
        // 19.44 out of the lowered line (6 below it). A shorter run's own ascent and descent scale with its size.)
        // (A top-aligned paragraph's lowering may stand in its style (`w:position` in the paragraph style's run properties).)
        lowTop = style.eastAsian["w:textAlignment"] == "top"
        lowNamed = lowTop ? _named(p, document)?.char.raised : nil
        if theme.wordRules, RichTextTheme.wordWindowsPages, !style.rightToLeft,
           style.lineHeightPoints == nil,
           besideLineIndents.isEmpty, keepClear == nil, RichLayout._paired(painter) == nil,
           p.runs.contains(where: { abs(raisedOf($0)) > 0.01 && $0.style.script == .normal }),
           // (A numbered line's raise (up to 2pt, lab pitch2) is taken off the number's rise instead: see the number span.)
           !(p.style.list != nil && !lowTop && p.runs.allSatisfy({ abs(raisedOf($0)) <= 2.01 })) {
            let metrics = painter.computeLineMetrics()
            let bottoms = RichLayout._rawLineBottoms(painter)
            let units = p.text.utf16.count
            let starts = _lineStarts(painter, _map(i), count: units)
            if metrics.count == bottoms.count, starts.count == metrics.count {
                var above = [Double](repeating: 0, count: metrics.count), below = above
                var tallest = [Double](repeating: 0, count: metrics.count)
                var unraised = [Bool](repeating: false, count: metrics.count)
                var plainRun = [Bool](repeating: false, count: metrics.count)
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
                    if abs(raisedOf(run)) < 0.01, run.style.script == .normal { plainRun[line] = true }
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
                    // (Word's print, lab raise259, Arial 9 and 11 at 240, 259, 276 and 360 auto: a raised line grows by the raise itself, 1, 2
                    // and 6 pt giving 1.0, 2.0 and 6.0 more between the plain lines around it at every multiple, and a lowered one by the
                    // lowering; the multiple never scales it.)
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
                            let r = RichLayout._shadowReach(sh, pt: run.style.fontSize ?? 0)
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
                    // (Lab raise259 holds lowered text only beside plain text on its line; a line whose every text run is lowered, as a
                    // lowered footnote beside its superscript mark, is unmeasured: at a multiple it keeps the engine's own height. Word's
                    // page, 1d944f7b footnote 6: its start stands 3.9 pt too low already, 2 pt more taller makes a table row overflow.)
                    // (Nor a run smaller than its line's text above single spacing: sa1 ad8f0ad1's 7 pt note mark raised 4 pt in 10 pt text at 273 keeps the
                    // engine's line; at single the raise is the growth, as verified.)
                    if style.lineSpacing - theme.lineSpacingReduction > 1.001, let sz = run.style.fontSize,
                       sz < (_named(p, document)?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize) - 0.01 { continue }
                    if pos < 0, !plainRun[line], style.lineSpacing - theme.lineSpacingReduction > 1.001 { continue }
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
                    RichLayout._pairedLines[ObjectIdentifier(painter)] = _PairedLines(painter: painter, shifts: shifts, saving: -acc)
                }
            }
        }
        if (besideLeftRoom != nil && !besideLineIndents.isEmpty) || keepClear != nil {
            RichLayout._registerPairs(painter, besideLeftRoom != nil ? besideLineIndents : [], push: keepClear)
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
        push = 0.0
        // Whether the paragraph's first line ends above a float that many
        // pixels down from its top: its space before as pagination keeps it
        // where the paragraph opens a section on a new page (less the space
        // after the paragraph before), then the line.
        firstLine = { [rl] in
            guard self.theme.wordRules, let first = self.painter.computeLineMetrics().first else { return nil }
            var top = self.before
            if self.i > 0, let xml = self.document.paragraphs[self.i - 1].style.sectionXML, !xml.containsSubstring("\"continuous\""), self._cells[self.i - 1] == nil {
                top = max(0, self.before - self._spacing(self.i - 1, self.document).after)
            }
            // (An empty line's height is its exact one, else its size's.)
            var line = first.height
            if let exact = self.style.lineHeightPoints, !self.style.lineHeightIsMinimum, exact > 0 { line = self._px(exact) }
            else if line < 1 { line = self._px(self.p.runs.first?.style.fontSize ?? self.theme.fontSize) }
            return (top, line)
        }
        lineEndsAbove = { down in
            guard let first = self.firstLine() else { return false }
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
        pushUnder = { [rl] foot in
            guard let first = self.firstLine(), first.line + self.before > 1 else { return foot }
            if let exact = self.style.lineHeightPoints, exact > 0, !self.style.lineHeightIsMinimum {
                let step = first.line + self.before
                let k = max(0, ((foot - first.top) / step - 0.001).rounded(.up))
                return max(0, first.top + k * step - self.before)
            }
            // (A line of spaces at a multiple above one steps by the single line, not the multiple; labs hinhdr2 (empty lines) did not fit this, so spaces only: hin b05873's
            // header, 18 spaces of Calibri 11 at 1.15 under a picture 72pt down, is set 6 steps of 13.43 from its
            // top, 80.6, in Word's print, and in labs hinhdr2 A, D, E, F, the picture's foot moving 5pt up and down;
            // ours set it at the foot.)
            if RichTextTheme.wordWindowsPages, self.style.lineHeightPoints == nil, self.style.lineSpacing > 1.001 || (self.headerTopOnPage != nil && !self.p.text.unicodeScalars.contains(where: { $0 == " " })), self.style.besideFloat == false,
               self.p.text.unicodeScalars.allSatisfy({ $0.value == 0xFFFC || $0 == " " }),
               case let step = (!self.p.text.unicodeScalars.contains(where: { $0 == " " }) ? self._markLineHeight(self.i, self.document, single: true) : first.line / self.style.lineSpacing) + self.before, step > 1 {
                let k = max(0, ((foot - first.top) / step - 0.001).rounded(.up))
                RuleTrace.hit("word-line-of-spaces-steps-clear-of-its-float-by-the-single-line")
                return max(0, first.top + k * step - self.before)
            }
            guard RichTextTheme.wordWindowsPages, self.style.lineHeightPoints == nil, case let half = self._firstLineGridHalf(self.i, self.document), half > 0.01,
                  case let step = first.line - half + self.before, step > 1 else { return foot }
            let k = max(0, ((foot - half - first.top) / step - 0.001).rounded(.up))
            return max(0, first.top + k * step - self.before)
        }
        // (A header's empty line steps down from the header's top by the single line, and stops at the first step where the pictures
        // wrapping around it, page-relative ones too, leave a gap as wide as its font size: dx2 cy 096a80c1's header, three tight pictures,
        // Word's line at step 3 where the right one clears and 125pt opens beside the middle one, not under the lowest foot.)
        headerStepped = false
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
                    // (Compatibility mode 14 and below: the empty line stays where it stands and the body is not pushed, whatever the pictures leave beside it:
                    // lab hdrbox, 827a8947's header, a text box and a tight picture, the body at the top margin in Word's print for six variants, a 60 pt box and a picture 47 pt down among them; the mode 15 lab hdrpoly stepped.)
                    while k < 60, (document.compatibilityMode ?? 12) >= 15 {
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
    }
}
