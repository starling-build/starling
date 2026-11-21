// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paragraph+Body4": step 4 of `_layoutParagraphBody`.
// A pure move, scripted (test/tools/split-paragraph.py): the bodies are as they were; the function's locals are the fields of `_ParaFrame`.

import Flutter
import FlutterSwiftBridge
import Foundation

extension _ParaFrame {
    func c4() -> Void {
        // (A box the text keeps above and below, standing part way down the paragraph that
        // holds its anchor: the lines that would meet it go under it — Word's print of
        // LibreOffice's tdf133924, "notBeside" 273pt down a paragraph of text.)
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
        wholePitchEquation = inline.contains { $0.image?.name == "m:oMath" && $0.image?.float == nil && _pageFill[$0.image?.id ?? ""] != nil }
        if equationLinesGrowAfterLayout, !wholePitchEquation, painter.strutStyle?.forceStrutHeight == true, keepClear == nil, RichLayout._paired(painter) == nil,
           let boxes = painter.inlinePlaceholderBoxes, boxes.count == inline.count, !boxes.isEmpty {
            let bottoms = RichLayout._rawLineBottoms(painter)
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
                RichLayout._pairedLines[ObjectIdentifier(painter)] = _PairedLines(painter: painter, shifts: shifts, saving: -acc)
            }
        }
        // (A tall equation on a line grid: Word's line is the equation's whole pitches (20d9968b's (1-r^n)/(1-r)^2 is two pitches, 36pt,
        // with the baseline 23.7 down it); the forced strut holds ours to one pitch and the box stands above the paragraph.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.cell == nil, !style.rightToLeft, _columns <= 1, painter.strutStyle?.forceStrutHeight == true,
           keepClear == nil, besideLineIndents.isEmpty, RichLayout._paired(painter) == nil,
           let boxes = painter.inlinePlaceholderBoxes, boxes.count == inline.count, !boxes.isEmpty {
            let bottoms = RichLayout._rawLineBottoms(painter)
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
                RichLayout._pairedLines[ObjectIdentifier(painter)] = _PairedLines(painter: painter, shifts: shifts, saving: -acc)
            }
        }
        // (A fraction in a line of "at least" spacing: Word's line is as tall as the text's strut or the fraction's own
        // ascent over the last line's foot, whichever is more: the gap from one baseline to the next is the larger of
        // the strut and the line above's descent plus this line's ascent. Lab frac3 case 10, 14pt at least, 11pt text and
        // fraction: 16.34 and 16.68 where the lines were all 14.0.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.cell == nil, !p.text.isEmpty, !style.rightToLeft, _columns <= 1,
           (style.lineHeightIsMinimum && (style.lineHeightPoints ?? 0) > 0 || style.lineHeightPoints == nil && abs(style.lineSpacing - 1) < 0.001), keepClear == nil, besideLineIndents.isEmpty,
           RichLayout._paired(painter) == nil, let boxes = painter.inlinePlaceholderBoxes, boxes.count == inline.count, !boxes.isEmpty {
            let bottoms = RichLayout._rawLineBottoms(painter)
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
                    RichLayout._pairedLines[ObjectIdentifier(painter)] = _PairedLines(painter: painter, shifts: shifts, saving: -acc)
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
           RichLayout._paired(painter) == nil, !p.text.isEmpty, let boxes = painter.inlinePlaceholderBoxes, boxes.count == inline.count, !boxes.isEmpty {
            let bottoms = RichLayout._rawLineBottoms(painter)
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
                        let pos = p.runs.first(where: { $0.style.inlineImage == img.id }).flatMap { $0.style.raised } ?? RichLayout._runPosition(img.sourceRunPropertiesXML) ?? 0
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
                        RichLayout._pairedLines[ObjectIdentifier(painter)] = _PairedLines(painter: painter, shifts: shifts, saving: -acc)
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
           keepClear == nil, besideLineIndents.isEmpty, RichLayout._paired(painter) == nil {
            let bottoms = RichLayout._rawLineBottoms(painter)
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
                    RichLayout._pairedLines[ObjectIdentifier(painter)] = _PairedLines(painter: painter, shifts: shifts, saving: acc)
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
               let pos = p.runs.first(where: { $0.style.inlineImage == img.id }).flatMap { $0.style.raised } ?? RichLayout._runPosition(img.sourceRunPropertiesXML) ?? 0
               return abs(pos) > 0.01
           }),
           besideLineIndents.isEmpty, keepClear == nil, RichLayout._paired(painter) == nil,
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
            let bottoms = RichLayout._rawLineBottoms(painter)
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
                        let pos = p.runs.first(where: { $0.style.inlineImage == img.id }).flatMap { $0.style.raised } ?? RichLayout._runPosition(img.sourceRunPropertiesXML) ?? 0
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
                    // (A tall picture on a line of its own, no text beside it, stays on the engine's pitch: e23ca36b's screenshots at 1.08 matched
                    // to 0.1 pt without the rule below, which gave each 2.6 pt more. Text beside it is a8f4dfcd's icons.)
                    if tallPic {
                        for (box, il) in zip(boxes, inline) where il.image != nil {
                            let r = box.toRect(), mid = r.top + r.height / 2
                            if let line = bottoms.firstIndex(where: { mid < $0 }), metrics[line].width <= r.width + 1 { above[line] = -1; below[line] = -1 }
                        }
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
                        RichLayout._pairedLines[ObjectIdentifier(painter)] = _PairedLines(painter: painter, shifts: shifts, saving: -acc, objects: true)
                    }
                }
            }
        }
    }
}
