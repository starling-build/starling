// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paragraph+Body3": step 3 of `_layoutParagraphBody`.
// A pure move, scripted (test/tools/split-paragraph.py): the bodies are as they were; the function's locals are the fields of `_ParaFrame`.

import Flutter
import FlutterSwiftBridge
import Foundation

extension _ParaFrame {
    func c3() -> Void {
        scriptsOnly = painter.strutStyle == nil && p.inlineImages.isEmpty && p.runs.contains { $0.style.script != .normal }
            && Set(painter.computeLineMetrics().map { ($0.height * 100).rounded() }).count == 1
        // (… nor does one whose runs differ in size, which has no strut
        // either: zh-31d580df's "(2)人員配置：…" — 10.5pt text and a 12pt
        // "（★參考撰寫說明2、3）" at the end, 1.25 lines — stood its first
        // line 5pt under Word's print.)
        // (Only where its first line is of one size and a later run differs:
        // a title whose first line mixes sizes — zh-454e2e29's 18pt, 14pt
        // and 24pt "（機關名稱機關代號）" — keeps its own.)
        mixedSizes = false
        latinFirstLine = false
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
                        if RichLayout._setsNoLine(ch) { continue }
                        let ea = RichLayout.isEastAsian(ch, hinted: hinted)
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
        w2Done = false
        w2Trim = 0.0   // what the engine's first line stands over the bullet line's ascent (its ink is lifted by it above)
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
           label.contains(where: { RichLayout.isEastAsian($0, hinted: true) }),
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
        _blk7()
    }
}
