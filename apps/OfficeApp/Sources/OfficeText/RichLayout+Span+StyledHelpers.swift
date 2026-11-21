// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "StyledHelpers": the local functions of `_spanStyled`, as methods

import Flutter
import FlutterSwiftBridge
import Foundation

extension _StyledFrame {
    func fitPaintedExtra(_ ch: Character, _ eaCh: Bool, _ g: Double, _ rs: CharStyle) -> Double {
        let em = (rs.fontSize ?? named?.char.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
        let wScale = RichTextTheme.wordWidthScale(rs.horizontalScale ?? named?.char.horizontalScale ?? 1, wordRules: theme.wordRules,
            eastAsiaFamily: rs.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? rs.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily)
        let latinFace = theme.faceResolver?(rs.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false)
        guard theme.wordRules, RichTextTheme.wordWindowsPages, ch.unicodeScalars.count == 1, g > 0.5,
              let u = ch.unicodeScalars.first?.value else { return 0 }
        if eaCh {
            let eaFace = theme.faceResolver?(rs.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                             ?? rs.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)
            if u >= 0xAC00 && u <= 0xD7A3 {
                let hEm = eaFace?.otherAdvances?[0xAC00].map { $0 * em * wScale } ?? em * wScale
                return (hEm < em * wScale ? abs(g - hEm) > 0.01 : g < hEm - 0.01) ? hEm - g : 0
            }
            // (A symbol of a Korean face is an em wide in Word, stretched by w:w like the Hangul: 10.44 at 12 pt w:w 87.)
            if u >= 0x2190 && u <= 0x266F, u != 0x2611 { let sEm = em * wScale; return g < sEm - 0.01 ? sEm - g : 0 }
            if u < 0x2E80 || (u >= 0x3000 && u < 0x3100) || (u >= 0xFF00 && u < 0xFF60),
               let w = (style(-1).fontWeight == .bold ? eaFace?.boldOtherAdvances : eaFace?.otherAdvances)?[u] { return w * em * wScale - g }
            return 0
        }
        if u >= 0x20, u <= 0x7E, let face = latinFace, let table = face.advanceTable(bold: style(0).fontWeight == .bold, italic: style(0).fontStyle == .italic),
           Int(u) - 0x20 < table.count, table[Int(u) - 0x20] > 0, let px = style(0).fontSize, px > 0.5 {
            return table[Int(u) - 0x20] * px / face.sizeScale - g
        }
        return 0
    }
    func fitSpacing() -> Double? {
        guard let g = fitGroup, !fitNone else { return nil }
        if let f = fitPitch { return f }
        fitBusy = true
        defer { fitBusy = false }
        var total = 0.0, count = 0, lastLength = 0
        var at = 0
        let units = Array(p.text.utf16)
        for r in p.runs {
            defer { at += r.length }
            guard tcFit ? at + r.length <= units.count : (RichLayout._fitText(r.style.keptXML)?.id == g.id && at + r.length <= units.count) else { continue }
            let piece = String(decoding: units[at ..< at + r.length], as: UTF16.self)
            lastLength = piece.count
            fitLastEnd = at + r.length
            for (k, ch) in piece.enumerated() {
                // (A space the paragraph sets half an em wide
                // (`wideSpaces`) is measured so, as it is painted:
                // 6 pt at 12, not the stand-in's 3.3.)
                if ch == " ", tcFit || ctx.wideSpaces.contains(at + k) {
                    total += _glyphWidth(style(-1), "\u{5355}") / 2
                } else if tcFit, let u = ch.unicodeScalars.first?.value, u >= 0xAC00, u <= 0xD7A3 {
                    // (A Hangul syllable is an em in Word's Korean faces, as it is drawn below.)
                    total += _glyphWidth(style(-1), "\u{5355}")
                } else {
                    let eaCh = RichLayout.isEastAsian(ch, hinted: hinted)
                    let g = _glyphWidth(style(eaCh ? -1 : 0), ch)
                    total += tcFit ? g : g + fitPaintedExtra(ch, eaCh, g, r.style)
                }
                count += 1
            }
        }
        let target = g.points * theme.pixelsPerPoint * scale
        var pitch: Double
        if tcFit {
            // (Word's fit text in a cell, Word for Windows, labs fit1 and mar1/mar2: Word works in 96-dpi screen pixels. Each side's
            // cell margin is rounded UP to a whole pixel, the room is the cell's width less those, and the spacing is a whole number
            // of pixels, rounded DOWN, over the gaps (the last letter is drawn apart). 23 of fit1's 24 rows match; the 0.76 px
            // the room is short of the cell, and which rows wrap their last letter, are OPEN.)
            fitLastSingle = false
            let pixel = 0.75 * theme.pixelsPerPoint * scale
            let slack = RichLayout._tcFitMarginSlack(p, document) * theme.pixelsPerPoint * scale
            let room = target + slack - 0.76 * pixel
            let gaps = max(count - 1, 0)
            pitch = gaps > 0 ? ((room - total) / Double(gaps) / pixel).rounded(.down) * pixel : 0
        } else {
            fitLastSingle = lastLength == 1
            let gaps = lastLength == 1 ? count - 1 : count
            pitch = gaps > 0 ? (target - total) / Double(gaps) : 0
            // (Word keeps the spacing in twips, rounding a spread up: zh-a4b0f6ea's
            // 单位(盖章)：…年   月   日 wants 0.073pt and Word sets 0.10, so 日 ends
            // 1.6pt past the group's width as Word's print does.)
            if pitch > 0, theme.wordRules, RichTextTheme.wordWindowsPages {
                let unit = 0.05 * theme.pixelsPerPoint * scale
                pitch = (pitch / unit - 1e-6).rounded(.up) * unit
            }
        }
        // (Where the run spacing is taken twice (`doubles`), so is the pitch: Word's step is one pitch more than the glyph's.)
        fitPitch = pitch
        return pitch
    }
    func style(_ kind: Int) -> TextStyle {
        if kind == -1000, let face = hyphenFace {
            var hyphen = run
            hyphen.fontFamily = face
            hyphen.hAnsiFontFamily = nil
            return theme.textStyle(for: hyphen, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, eastAsian: false, gridPitch: pitch,
                                   characterClass: nil, characterGrid: grid, scriptHidden: true)
        }
        if !fitBusy, !plainPiece, !latinNoScale, let s = styles[kind] { return s }
        var styled = run
        var symbolOnce = false
        let grown = wholeRaised ? theme.raisedLineHeight(for: run, in: p.style, named: named, eastAsian: kind < 0, gridPitch: pitch) : nil
        if let grown { styled.raised = grown.raise }
        if kind == -3, let (alt, _) = uncovered { styled.eastAsiaFontFamily = alt }
        // (A circle or square in a run that names only a missing Korean ascii face is drawn in Malgun, but its line is that ascii face's
        // Batang line, not the style's East Asian face's: xd 4fabe1f2's "○○" runs in 바탕글, whose 함초롬바탕 stood the line Malgun-tall,
        // 37.9 pt from the line above where Word's print has 35.4 at 1.7 lines.)
        if kind == -4, run.eastAsiaFontFamily == nil, theme.wordRules, RichTextTheme.wordWindowsPages, document.usesEastAsianLayout,
           let f = run.fontFamily, theme.faceResolver?(f, true)?.malgunSymbols == true {
            RuleTrace.hit("korean-circle-in-ascii-only-run-keeps-the-ascii-faces-line")
            styled.eastAsiaFontFamily = f
            symbolOnce = true  // (its spacing is taken once: see malgun-shape-takes-spacing-once)
        }
        if kind == -5, let h = run.hAnsiFontFamily ?? named?.char.hAnsiFontFamily { styled.eastAsiaFontFamily = h }
        if kind <= -10, let chain, -10 - kind < chain.count { styled.eastAsiaFontFamily = chain[-10 - kind].family }
        var s = theme.textStyle(for: styled, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, eastAsian: kind < 0, gridPitch: pitch,
                                characterClass: classed && kind >= 0 ? kind : nil, characterGrid: kind < 0 ? ideographGrid : latinGrid, scriptHidden: true)
        if doubles, kind < 0, !symbolOnce { s = s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + spacing) }
        // (A run set in a chain face (Yu Gothic, JhengHei) has that face's own ascent and descent: Word's line takes the larger above and
        // below the baseline over the faces on it, so a Mincho line with one fallen-back character is 1.7 pt shorter above the next line
        // than the 0.8/0.2 split of the face's height says. lab cm236c (2026-11-15), fbL1 18.12 / fbL2 17.64 / fbBoth 20.04 at 12 pt.)
        if kind <= -10, theme.wordRules, RichTextTheme.wordWindowsPages, subsetFace?.chainFaceLines == true, let chain, -10 - kind < chain.count, let size = s.fontSize, size > 0.5,
           let m = RichLayout._chainFaceLines[chain[-10 - kind].family] {
            let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
            s = s.copyWith(ascentOverride: m.0 * multiple * size, descentOverride: m.1 * multiple * size, height: (m.0 + m.1) * multiple, leadingDistribution: .even)
        }
        // (A right-to-left run in a complex face Word lacks, drawn in Arial, carries Arial's own line (1.149 em) itself: where a Sakkal Majalla run
        // makes the paragraph's heights differ there is no strut, and each line took the Noto stand-in's 17.1 pt where Word's step 14.8. dx2 ur 84f36322.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, kind >= 0, run.rightToLeft, s.ascentOverride == nil, p.style.lineHeightPoints == nil, pitch == nil,
           let size = s.fontSize, size > 0.5, run.ruby == nil,
           case let cs = run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily,
           let face = theme.complexFace(cs, latin: run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily, letters: run.csLetters), face.arialStandIn {
            RuleTrace.hit("word-arial-stand-in-complex-run-keeps-arials-line")
            let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
            let sp = RichLayout._multipleSplit(ascent: 0.905, descent: 1.149 - 0.905, multiple: multiple)
            s = s.copyWith(ascentOverride: size * sp.0, descentOverride: size * sp.1, height: 1.149 * multiple, leadingDistribution: .even)
        }
        if kind == -4, let cjk = RichLayout._cjkFaceFamily {
            RuleTrace.hit("word-east-asian-shape-is-the-cjk-faces-glyph")
            s = s.copyWith(fontFamily: cjk)
        }
        // (A space set in the ideographs' face keeps the stand-in's width.)
        // (… and no line of its own: the face a space resolves to
        // is not always the ideographs', and its descent made the
        // line taller — zh-1563bd74's footer line, 19.0pt on the
        // Mac against the ideographs' 18.6, and Word's lab `hfl`
        // gives trailing spaces no height at all.)
        if kind == -2 { s = s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + _spaceWidth(style(classed ? RichResolvedFace.characterClass(" ") : 0)) - _spaceWidth(s), height: RichLayout.shadeShows(run.highlight) ? s.height : 0.01) }
        // (Set to the original's widths, the stand-in's own
        // kerning is no part of them: Arial's pair of ones.)
        if kind >= 0, latinFace?.advances != nil || (latinFace?.boldAdvances != nil && s.fontWeight == .bold) { s = s.copyWith(fontFeatures: [FontFeature("kern", 0)]) }
        // (Yu Gothic's Latin, where Word's box lacks the Hangul-named face, carries no pair kerning in the print; 22de7d.)
        if kind >= 0, yuOfMissingHangul, !aumsLatin { s = s.copyWith(fontFeatures: (s.fontFeatures ?? []) + [FontFeature("kern", 0)]) }
        if kind >= 0, let indic, indic.scale != 1, !latinNoScale { s = s.copyWith(scaleX: indic.scale) }
        // (The run's own line is the face's, not the stand-in's, where the face's is the shorter: Aparajita's 1.18 em (a516bfe9: 2.7 to 92.9) where Noto
        // Sans Devanagari's is taller; the joiner above only raises a line.)
        if kind >= 0, let indic, (indic.face == "kokila" && (kokilaLatin || text.unicodeScalars.contains(where: { RichLayout._isIndic($0.value) }))) || (indic.face == "utsaah" && utsaahLatin) || (indic.face == "malgun gothic" && malgunLatin) || (indic.face == "yu gothic" && (aumsLatin || aumsYuInIndic)) || indic.face == "vijaya" || indic.face == "latha" || indic.face == "shonar bangla" || indic.face == "leelawadee ui" || (namedFace != nil && (namedFace != "mangal" || namedKalimati)) || (indic.face == "nirmala ui" && !plainPiece && !p.text.unicodeScalars.contains(where: { RichLayout._tamil.contains($0.value) })), let m = RichLayout._indicLines[(indic.face == "shonar bangla" && (run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold)))) ? "shonar bangla bold" : indic.face], p.style.lineHeightPoints == nil, let size = s.fontSize, size > 0.5 {
            // (Kokila's line: its own ascent and descent, above and below the baseline, for every run on the line: the stand-ins'
            // (Carlito's, Noto's) are taller above and set the line 2-3 pt low and 1.4 pt per line too far apart.)
            // (A multiple under single too: dx2 hin-z20740649's 0.9 lines are 13.5 pt apart in Word's print, Kokila's 15.0 x 0.9.)
            let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
            // (Word keeps the baseline where single spacing puts it and gives the multiple's extra below it; a multiple under single is cut from
            // the top. lab mmatrix2 (2026-11-09): Kokila 18's gap to the next line is 40.8 / 43.9 / 47.0 / 51.1 for a previous 1.0 / 1.15 / 1.3 / 1.5
            // whatever the next multiple is; `RichLayout._multipleSplit`.)
            // (Kokila only so far: the other faces' lines were fitted with the extra spread over both sides; each gets the shared split when its own dx2 documents agree.)
            let split = indic.face == "kokila" || indic.face == "latha" || indic.face.hasPrefix("shonar bangla") ? RichLayout._multipleSplit(ascent: m.0, descent: m.1, multiple: multiple) : (m.0 * multiple, m.1 * multiple)
            // (A character scale (w:w) is laid out as a larger size; the line's height follows the authored size: dx2 3f7da49c's 105% title, 23.7 pt in Word, 24.9 here.)
            let wScale = RichTextTheme.wordWidthScale(run.horizontalScale ?? named?.char.horizontalScale ?? 1, wordRules: theme.wordRules,
                eastAsiaFamily: run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily)
            let lineSize = wScale > 0.01 ? size / wScale : size
            // (A run that names Calibri takes Calibri's deeper descent (win 550/2048 = 0.2686 em) under the Nirmala line even where the line holds no Latin
            // letter: lab dpitch (Word, 12 pt): Calibri-named Devanagari lines are 16.2 pt, Arial- and Times-named 15.96. d912c25b p2.)
            var below = split.1
            if indic.face == "nirmala ui", theme.wordRules, RichTextTheme.wordWindowsPages,
               (run.fontFamily ?? named?.char.fontFamily ?? "").trimmingWhitespace().lowercased() == "calibri",
               (run.complexFontFamily ?? named?.char.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "calibri" {
                below = max(below, 550.0 / 2048 * multiple)
            }
            // (Lao in Leelawadee UI beside spaces: Word draws the spaces in Browallia New, whose deeper descent sets the line, 1.08 + 0.372 em
            // = 1.452 (pitch 18.75 pt at 12 pt on 259; dx2 30f73046 page 2), where Leelawadee's own line is 1.36.)
            if indic.face == "leelawadee ui", theme.wordRules, RichTextTheme.wordWindowsPages,
               p.text.unicodeScalars.contains(where: { $0.value >= 0x0E81 && $0.value <= 0x0EDF }), p.text.unicodeScalars.contains(where: { $0.value == 0x20 }) {
                RuleTrace.hit("word-lao-line-with-spaces-takes-browallia-descent")
                below = max(below, 0.372 * multiple)
            }
            s = s.copyWith(ascentOverride: split.0 * lineSize, descentOverride: below * lineSize, height: (m.0 * multiple + (below == split.1 ? m.1 * multiple : below)) * lineSize / size, leadingDistribution: .even)
        }
        // (Latin letters in a run whose ascii face is Nirmala UI itself (Semilight too) beside Indic text are drawn in Nirmala, so they take its line and add no Latin
        // stand-in's: dx2 426d1cc2's "l:f" in a Punjabi paragraph went 21.1 to 23.1 pt once the line was no longer held to one pitch.)
        if kind >= 0, plainPiece || indic == nil, indic == nil || indic?.face == "nirmala ui", theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil, let size = s.fontSize, size > 0.5,
           { let f = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased(); // (Spaces and marks in a run of their own (no letters, Latin or Indic) are not Nirmala's line: af19d946 ", " runs, Calibri in Word'"'"'s print; Arial'"'"'s marks are.)
               return (f.hasPrefix("nirmala ui") && text.unicodeScalars.contains(where: { ($0.value < 0x250 && ($0.properties.isAlphabetic || ($0.value >= 0x30 && $0.value <= 0x39))) || (RichLayout._isIndic($0.value) && !(run.keptXML?.containsSubstring("<w:cs") ?? false)) }))  || f == "arial" }(),
           !p.text.unicodeScalars.contains(where: { RichLayout._tamil.contains($0.value) }),
           indic != nil || (!text.unicodeScalars.contains(where: { RichLayout._isIndic($0.value) }) && text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 }) && p.text.unicodeScalars.contains(where: { RichLayout._indic.contains($0.value) }))
               // (A run of only dandas (। ॥) in a Nirmala UI face has no letter, so no Indic face is chosen for it, and its stand-in's taller line deepened the line 1.2 pt: dx2 bea98273 p5, 15.28 pt against Word's 14.04. The danda is Nirmala's.)
               || (!text.isEmpty && text.unicodeScalars.allSatisfy({ $0.value == 0x964 || $0.value == 0x965 }) && p.text.unicodeScalars.contains(where: { RichLayout._indic.contains($0.value) && $0.properties.isAlphabetic })),
           let m = RichLayout._indicLines["nirmala ui"] {
            let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
            // (A Nirmala-named run's pieces carry the line's height too; an Arial piece only the ascent/descent split: a line height on its stand-in raised the
            // line 0.6 pt (dx2 f96948dd 16.57 against Word's 15.96, 1ca6c218's Arial-only title line 32 against 28.6), where the split alone stacks correctly.)
            let nirmalaNamedRun = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased().hasPrefix("nirmala ui")
            s = s.copyWith(ascentOverride: m.0 * multiple * size, descentOverride: m.1 * multiple * size, height: nirmalaNamedRun ? (m.0 + m.1) * multiple : nil, leadingDistribution: nirmalaNamedRun ? .even : nil)
        }
        // (A full stop in a run of a face Windows lacks (the Latin face of a Sinhala paragraph) is drawn in Sylfaen by Word, whose win descent 635/2048 = 0.31 em
        // is deeper than Nirmala UI's 0.251: the Sinhala line is Nirmala's ascent 1.079 over Sylfaen's descent, 16.68 pt at 12 pt, 29.16 at 21 pt, against 15.96 and
        // 28.0 (dx2 827a8947, Word's print: every line with a Sylfaen stop; the lines without stand 14.64 at 11 pt). Sylfaen: /data/corpus-cache/metrics/indic-si-ta-20261121.)
        if kind >= 0, theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil, let size = s.fontSize, size > 0.5,
           text.unicodeScalars.contains(where: { $0.value == 0x2E }), p.text.unicodeScalars.contains(where: { $0.value >= 0xD80 && $0.value <= 0xDFF }),
           case let ff = (run.fontFamily ?? named?.char.fontFamily ?? "").trimmingWhitespace().lowercased(), !ff.isEmpty, !WordWindowsFaces.names.contains(ff) {
            RuleTrace.hit("word-sinhala-line-full-stop-in-sylfaen-descent")
            let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
            s = s.copyWith(ascentOverride: 2210.0 / 2048 * multiple * size, descentOverride: 635.0 / 2048 * multiple * size, height: (2210.0 + 635) / 2048 * multiple, leadingDistribution: .even)
        }
        // (A digit, a mark or a no-break space between Nirmala UI's words, in a run whose Latin face is Calibri, is on its line: the line takes Calibri's deeper descent
        // (win 550/2048 = 0.2686 em against Nirmala's 0.251) even where the glyph is drawn in Nirmala; a plain space does not. Word's print of dx2 f4abc45d (Punjabi, 11 pt):
        // lines with an apostrophe, comma, colon, digit or NBSP stand 14.88 apart, the others 14.63; 6af76fa9 likewise.)
        if kind >= 0, plainPiece, indic?.face == "nirmala ui", theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil, let size = s.fontSize, size > 0.5,
           (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily ?? "").trimmingWhitespace().lowercased() == "calibri",
           text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 }),
           !p.text.unicodeScalars.contains(where: { RichLayout._tamil.contains($0.value) }),
           p.text.unicodeScalars.contains(where: { $0.value >= 0xA00 && $0.value < 0xA80 }),
           let m = RichLayout._indicLines["nirmala ui"] {
            let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
            s = s.copyWith(ascentOverride: m.0 * multiple * size, descentOverride: max(m.1, 550.0 / 2048) * multiple * size, height: (m.0 + max(m.1, 550.0 / 2048)) * multiple, leadingDistribution: .even)
        }
        // (Garamond's Latin beside a Nirmala UI line: a line is its tallest ascent over its deepest descent, and Garamond's own descent (0.2632 em, ascent 0.8618:
        // 1.125 em, Word's 12.36 pt at 11) is deeper than Nirmala's 0.251 where its stand-in's is shallower. Word's Bengali lines with Garamond runs are 14.76 at 11 pt and
        // 14.1 at 10.5 (Nirmala alone 14.63, 13.97). dx2 bea98273.)
        if kind >= 0, theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil, indic == nil, let size = s.fontSize, size > 0.5,
           (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "garamond",
           !text.unicodeScalars.contains(where: { RichLayout._isIndic($0.value) }), text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 }),
           p.text.unicodeScalars.contains(where: { RichLayout._indic.contains($0.value) }), !p.text.unicodeScalars.contains(where: { RichLayout._tamil.contains($0.value) }) {
            let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
            s = s.copyWith(ascentOverride: 0.8618 * multiple * size, descentOverride: 0.2632 * multiple * size)
        }
        // (A run of Latin in a face other than Kokila inside a Kokila paragraph: Word stands its line on that face's ascent (above Kokila's) and keeps the
        // Kokila split below it, at a line multiple too (dx2 cbb7ae39's Times New Roman "IRB", lab cb7; its 1.57-line paragraphs: the line is 2.0 pt taller, the
        // extra under the baseline unchanged). White space and the invisible marks beside Kokila text set no line of their own.)
        // (Shonar Bangla beside Arial: the same line, the Latin face's ascent (with its line gap) over the Bengali face's descent; lab stk1.)
        let latinOwner: String? = paragraphLatinOwner
        if kind >= 0, theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, !kokilaLatin || (run.keptXML?.containsSubstring("<w:cs") ?? false), p.style.lineHeightPoints == nil,
           let latinOwner, let m = RichLayout._indicLines[latinOwner], let size = s.fontSize, size > 0.5,
           !text.unicodeScalars.contains(where: { RichLayout._isIndic($0.value) }),
           p.text.unicodeScalars.contains(where: { RichLayout._indic.contains($0.value) }) || (latinOwner == "shonar bangla" && text.unicodeScalars.contains(where: { $0.value == 0xA0 }) && RichLayout._bengaliMissingFace((p.style.mark?.fontFamily ?? "").trimmingWhitespace().lowercased(), document) == "shonar bangla") {
            // (A real no-break space counts in its own Latin face even in a paragraph with no Bengali letter, where the paragraph's mark is in the missing Bengali face (a line the Shonar one sets): lab cambsp3, Cambria or Calibri 35.2 to 37.2; Cambria-marked lines stay at Cambria's.)
            // (Latin letters stack only when drawn in a face other than the line's Indic face: a run whose ascii face IS its complex face, such as Shonar Bangla on both, takes that face's own line and adds no Latin ascent; dx2 3f7da49c.)
            let ownAscii: String = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
            let ownComplex: String = (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
            let ownIndic: Bool = RichLayout._bengaliMissingFace(ownAscii, document) == "shonar bangla"
            let ownFace: Bool = latinOwner == "shonar bangla" && ownAscii == ownComplex && ownIndic
            let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
            let split = RichLayout._multipleSplit(ascent: m.0, descent: m.1, multiple: multiple)
            var above = split.0 * size
            // (A run with the w:cs flag is drawn wholly from its complex-script face: Kokila's "(" in dx2 cbb7ae39's first lines, Times New Roman's where cs is the major bidi face.)
            let csFlag = (run.keptXML?.containsSubstring("<w:cs") ?? false)
            let csFace = (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
            if !ownFace, text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 && (latinOwner != "shonar bangla" || !ownIndic || $0.properties.isAlphabetic || ($0.value >= 0x30 && $0.value <= 0x39) || $0.value == 0xA0) }), !(csFlag && csFace == "kokila"),
               let b = theme.baseline(for: run, in: { var single = p.style; single.lineSpacing = 1; return single }(), named: named, eastAsian: false, gridPitch: pitch, centresInLine: document.spacesForUnderline),
               let pt = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize, pt > 0.5 {
                above = max(above, b / pt * size)
            }
            s = s.copyWith(ascentOverride: above, descentOverride: split.1 * size, height: (above + split.1 * size) / size, leadingDistribution: .even)
        }
        // (Latin text, digits and marks whose own (ascii) face is Noto Sans Tamil, which Windows lacks: Word draws them in Mangal, and every
        // line holding one, wrapped or not, is Mangal's 1.680 em tall (1.241 above, 0.4385 below), also in a paragraph with no Tamil letter.
        // xd c016493b's rule of dashes wraps to a second line of 20.16 pt, the author block's URL line 20.16.)
        if kind >= 0, theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil, let size = s.fontSize, size > 0.5,
           !text.unicodeScalars.contains(where: { RichLayout._isIndic($0.value) }), text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 }),
           RichLayout._latinInNotoTamil(run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? ""),
           let m = RichLayout._indicLines["mangal"] {
            RuleTrace.hit("word-latin-run-in-noto-sans-tamil-sets-mangals-line")
            let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
            let split = RichLayout._multipleSplit(ascent: m.0, descent: m.1, multiple: multiple)
            s = s.copyWith(ascentOverride: split.0 * size, descentOverride: split.1 * size, height: (split.0 + split.1) * size / size, leadingDistribution: .even)
        }
        // (Latin letters set in Shruti (the run's own ascii face, the file naming it): Word sets Shruti's own line, 1.68 em, a Latin line
        // that is 13.4 pt in the stand-in at 11 pt against Word's 18.5: sa1 2b3c3b42's header lines in Shruti.)
        if kind >= 0, theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil, let size = s.fontSize, size > 0.5,
           !text.unicodeScalars.contains(where: { RichLayout._isIndic($0.value) }), text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 }),
           let face = Optional((run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()), face == "shruti",
           let m = RichLayout._indicLines[face] {
            RuleTrace.hit("word-latin-run-in-shruti-sets-shrutis-line")
            let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
            let split = RichLayout._multipleSplit(ascent: m.0, descent: m.1, multiple: multiple)
            s = s.copyWith(ascentOverride: split.0 * size, descentOverride: split.1 * size, height: (split.0 + split.1) * size / size, leadingDistribution: .even)
        }
        if kind >= 0, let indic, indic.face == "aparajita" || indic.face == "vijaya", let m = RichLayout._indicLines[indic.face], p.style.lineHeightPoints == nil, let size = s.fontSize, size > 0.5 {
            let multiple = p.style.lineSpacing > 1 ? p.style.lineSpacing : 1
            s = s.copyWith(height: (m.0 + m.1) * multiple, leadingDistribution: .even)
        }
        if let grown, s.fontSize ?? 0 > 0.5 { s = s.copyWith(height: grown.height) }
        // (Thai in Browallia New or Angsana New: every run, Latin and Thai, carries its face's own split of the line (hhea ascent and
        // descent, by weight), so a line is its tallest ascent over its deepest descent, as Word's: a bold run raises only the lines it is
        // on (xd b96afb37 20.8 pt, e93587db 19.0 beside 20.6), with no stacking of the 0.82-size Thai stand-in on the Latin one.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.lineHeightPoints == nil, s.ascentOverride == nil,
           let size = s.fontSize, size > 0.5, let h = s.height, let split = RichLayout._thaiLineSplit(s.debugLabel, bold: s.fontWeight == .bold), thaiParagraph {
            s = s.copyWith(ascentOverride: size * h * split, descentOverride: size * h * (1 - split), leadingDistribution: .even)
        }
        // (Yu Gothic and Yu Mincho ideographs stand a line on the face's own split, 1.18 em above the baseline and 0.5 below
        // (`EastAsianFace.baseline`), whatever else is in the paragraph: the stand-in's own split, 0.8 above, lifted the title lines of
        // xb jpn 12d9fb 2.6pt (a Latin-only line among them kept a paragraph strut off), Word's first baseline 18.8 at 16pt, ours 21.4.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, kind < 0, pitch == nil, p.style.lineHeightPoints == nil, s.ascentOverride == nil,
           p.style.lineSpacing > 0, let size = s.fontSize, size > 0.5,
           let fam = (run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily)?.trimmingWhitespace().lowercased(),
           let face = theme.faceResolver?(fam, true),
           ["游ゴシック", "yu gothic", "游明朝", "yu mincho"].contains(fam) || face.standsAsYuGothic && run.ruby == nil {
            let bold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
            if let t = (bold ? face.boldBaseline : nil) ?? face.baseline, let nat = (bold ? face.boldHeight : nil) ?? face.naturalHeight {
                RuleTrace.hit("word-yu-ideograph-line-stands-on-its-own-ascent")
                let sp = RichLayout._multipleSplit(ascent: t, descent: nat - t, multiple: p.style.lineSpacing)
                s = s.copyWith(ascentOverride: size * sp.0, descentOverride: size * sp.1, height: nat * max(1, p.style.lineSpacing), leadingDistribution: .even)
            }
        }
        // (A Latin stretch in a paragraph that stands its ideographs on Yu's own split keeps its face's baseline too, the line multiple's
        // extra below it as in a Latin-only paragraph, not shared out above: xb jpn 12d9fb's subtitle, "―Amazon" 5 pt low, the next line 6 high.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, kind >= 0, pitch == nil, p.style.lineHeightPoints == nil, s.ascentOverride == nil,
           p.style.lineSpacing > 1, let size = s.fontSize, size > 0.5, run.ruby == nil,
           let fam = (run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily)?.trimmingWhitespace().lowercased(),
           ["游ゴシック", "yu gothic", "游明朝", "yu mincho"].contains(fam) || theme.faceResolver?(fam, true)?.standsAsYuGothic == true,
           p.text.unicodeScalars.contains(where: { $0.value >= 0x3040 && $0.value < 0xA000 }),
           let latin = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily)?.trimmingWhitespace(),
           let face = theme.faceResolver?(latin, false) {
            let bold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
            var single = p.style; single.lineSpacing = 1
            let nat0 = (bold ? face.boldHeight : nil) ?? face.naturalHeight ?? theme.naturalLineHeight(family: face.family, bold: bold, italic: run.italic)
            if let b = theme.baseline(for: run, in: single, named: named, eastAsian: false, gridPitch: pitch), let pt = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize, pt > 0.5,
               case let t = b / pt, case let nat = nat0 {
                RuleTrace.hit("word-latin-beside-yu-keeps-baseline-extra-below")
                let sp = RichLayout._multipleSplit(ascent: t, descent: nat - t, multiple: p.style.lineSpacing)
                s = s.copyWith(ascentOverride: size * sp.0, descentOverride: size * sp.1, height: nat * p.style.lineSpacing, leadingDistribution: .even)
            }
        }
        if mixedLatinFaces, kind >= 0, pitch == nil, s.ascentOverride == nil, p.style.lineSpacing > 0, run.ruby == nil, run.emphasis == nil,
           let size = s.fontSize, size > 0.5, s.height != nil, !(index.map { _verticalBody($0) } ?? false),
           !text.isEmpty, text.unicodeScalars.allSatisfy({ $0.value < 0x250 || ($0.value >= 0x2000 && $0.value <= 0x2BFF) || ($0.value >= 0xFB00 && $0.value <= 0xFB06) }),
           !((run.fontFamily ?? named?.char.fontFamily).map { theme.isSymbolFace?($0.trimmingWhitespace()) ?? false } ?? false) {
            let bold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
            let italic = run.italic || ((named?.char.italic ?? false) && !run.off.contains(.italic))
            let latin = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily)?.trimmingWhitespace()
            let face = latin.flatMap { theme.faceResolver?($0, false) }
            // (Only a face whose line Word's metrics give: a stand-in's own ascent and descent are not the face's.)
            let own: (Double, Double)? = {
                let drawn = theme.faceAscentDescent(family: face?.family ?? latin ?? "", bold: bold, italic: italic)
                guard let t = (bold ? face?.boldBaseline : nil) ?? face?.baseline else { return nil }
                guard let d = ((bold ? face?.boldHeight : nil) ?? face?.naturalHeight).map({ $0 - t }) ?? drawn?.1 else { return nil }
                return (t, d)
            }()
            if let ad = own {
                let asc = ad.0, nat = ad.0 + ad.1
                RuleTrace.hit("word-line-of-mixed-latin-faces-is-tallest-ascent-over-deepest-descent")
                let sp = RichLayout._multipleSplit(ascent: asc, descent: nat - asc, multiple: p.style.lineSpacing)
                // (A character scale (w:w) is laid out as a larger size; the line's height follows the authored size: lab tahcal at 105%.)
                let wScale = RichTextTheme.wordWidthScale(run.horizontalScale ?? named?.char.horizontalScale ?? 1, wordRules: theme.wordRules,
                    eastAsiaFamily: run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily)
                let lineSize = wScale > 0.01 ? size / wScale : size
                s = s.copyWith(ascentOverride: lineSize * sp.0, descentOverride: lineSize * sp.1, height: nat * max(1, p.style.lineSpacing) * lineSize / size, leadingDistribution: .even)
                s = s.copyWith(debugLabel: (s.debugLabel ?? "") + " mixed-latin-line")
            }
        }
        // (A run with emphasis marks makes its line 0.31 em taller on their side: off a grid, single spacing, horizontal.)
        if theme.wordRules, run.emphasis != nil, run.ruby == nil, s.fontSize ?? 0 > 0.5, gridPitchIsNil(pitch), p.style.lineHeightPoints == nil,
           abs(p.style.lineSpacing - 1) < 0.005, s.ascentOverride == nil, !(index.map { _verticalBody($0) } ?? false),
           let h = theme.emphasisLine(for: run, in: p.style, named: named, eastAsian: kind < 0, gridPitch: pitch), let size = s.fontSize {
            s = s.copyWith(ascentOverride: size * (h.height - h.descent), descentOverride: size * h.descent, height: h.height, leadingDistribution: .even)
        }
        // (A run with ruby over it makes its line room for the ruby.)
        if theme.wordRules, run.ruby != nil, s.fontSize ?? 0 > 0.5,
           var h = theme.rubyLine(for: run, in: p.style, named: named, eastAsian: kind < 0, gridPitch: pitch, vertical: index.map { _verticalBody($0) } ?? false) {
            let verticalHere = index.map { _verticalBody($0) } ?? false
            if h.raise != 0, !verticalHere, !_rubyShiftApplies(p, named: named, ruby: run, pitch: pitch) { h.raise = 0 }
            s = s.copyWith(height: h.height)
                    if verticalHere, pitch != nil, p.style.lineHeightPoints == nil, h.raise != 0 { s = s.copyWith(leadingDistribution: .even, debugLabel: (s.debugLabel ?? "") + " vruby-line") }
            // (Off a grid the room for the ruby is all over the baseline, not shared with the line's foot:
            // xb jpn 231fe1 p1 "申請者" under ﾌﾘｶﾞﾅ stands 7pt lower, the next paragraph where it was. Single spacing only: at 1.15 Word's ruby line is shorter, lo-181b561b0a.)
            if gridPitchIsNil(pitch), p.style.lineHeightPoints == nil, p.style.lineSpacing > 0.995, h.descent > 0, s.ascentOverride == nil, let size = s.fontSize {
                s = s.copyWith(ascentOverride: size * (h.height - h.descent), descentOverride: size * h.descent, leadingDistribution: .even, debugLabel: (s.debugLabel ?? "") + " ruby-line")
            }
            if h.raise != 0, NativeParagraphBuilder.supportsBaselineShift, !verticalHere {
                s = s.copyWith(baselineShift: (s.baselineShift ?? 0) - h.raise * theme.pixelsPerPoint * scale)
            }
        } else if mixedRubyRaise != 0, run.ruby == nil, s.fontSize ?? 0 > 0.5, !(index.map { _verticalBody($0) } ?? false) {
            // (The rest of a one-line paragraph moves with its ruby's base.)
            s = s.copyWith(baselineShift: (s.baselineShift ?? 0) - mixedRubyRaise * theme.pixelsPerPoint * scale)
        }
        // (A vertical ruby paragraph on a grid has no strut, so a space in another face (a full-width space, a Latin blank) would set its
        // own deeper line: every plain run takes the ascent and descent its ideographs have. lab a_ruby: plain column 18.75, was 19.77.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, run.ruby == nil, s.fontSize ?? 0 > 0.5, pitch != nil, p.style.lineHeightPoints == nil,
           s.ascentOverride == nil, index.map({ _verticalBody($0) }) == true, p.runs.contains(where: { $0.style.ruby != nil }) {
            if let ref = _vrubyPlain {
                s = s.copyWith(ascentOverride: ref.ascent * (s.fontSize ?? 1) / ref.size, descentOverride: ref.descent * (s.fontSize ?? 1) / ref.size, leadingDistribution: .even)
            } else if kind < 0, let size = s.fontSize {
                let tp = TextPainter(text: TextSpan(text: "山", style: s), textDirection: .ltr)
                tp.layout(minWidth: 0, maxWidth: Double.infinity)
                if let m = tp.computeLineMetrics().first { _vrubyPlain = (m.ascent, m.descent, size) }
            }
        }
        // (A run with a text shadow (w14:shadow) makes its line taller by the shadow's reach: the blur radius past the offset,
        // below and above the face's own line. Lab hdrsup v7 against v10, 72 pt Copperplate Gothic Light, shadow 3 pt out at 45 degrees
        // blurred 4 pt: the baseline falls 1.92 pt (4 - 3 sin 45 = 1.88) and the body 8.04 (4 + 3 sin 45 = 6.12 more below).)
        if theme.wordRules, RichTextTheme.wordWindowsPages, let sh = run.shadow ?? named?.char.shadow, !sh.glow, sh.blur > 0, sh.scale > 0,
           let size = s.fontSize, size > 0.5, !(index.map { _verticalBody($0) } ?? false),
           let latin = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily)?.trimmingWhitespace(),
           let face = theme.faceResolver?(latin, false),
           let pt = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize, pt > 0.5 {
            var single = p.style; single.lineSpacing = 1
            let bold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
            let line = (bold ? face.boldHeight : nil) ?? face.naturalHeight ?? theme.naturalLineHeight(family: face.family, bold: bold, italic: run.italic)
            if let b = theme.baseline(for: run, in: single, named: named, eastAsian: false, gridPitch: pitch), case let asc = b / pt, asc > 0.3, line > asc {
                RuleTrace.hit("word-text-shadow-reaches-the-line")
                let k = theme.pixelsPerPoint * scale
                // (The glyphs are set down by the reach above them and the line grows by the reach below as well: the line's own
                // ascent stays, the paint takes the baseline from the face.)
                // (Lab shadow2, Word's print, Calibri, blur 4 dist 3 at 45 degrees (full reach 8 pt): the line grows by 2.28 pt at 12, 3.72 at 24,
                // 4.92 at 36, 6.72 at 55, 8.04 at 72, the same for a style's shadow and a direct one, 1.15 spacing multiplying it;
                // blur 3 dist 1.8 at 55 grows 5.04 = 0.84 of its reach 6. So the reach counts by a fraction of the size, whole from 72 pt.)
                let (aboveReach, belowReach) = RichLayout._shadowReach(sh, pt: pt)
                let above = aboveReach * k, below = belowReach * k
                // (Lab shadow3: when every run of the paragraph is raised, the line takes the whole reach, above and below; see the paragraph pass.)
                let allRaised: Bool = {
                    let u = Array(p.text.utf16); var at = 0
                    for r in p.runs where r.length > 0 {
                        defer { at += r.length }
                        guard at < u.count else { break }
                        if u[at ..< min(u.count, at + r.length)].contains(where: { $0 > 0x20 }), (r.style.raised ?? 0) == 0 { return false }
                    }
                    return true }()
                let up = s.ascentOverride ?? asc * size, down = (s.descentOverride ?? (line - asc) * size) + above + below
                // (A raised or lowered run's box takes no line of its own: its shadow's reach above it is carried in the label for the
                // line pass, `_strut`, which grows the line by it. Lab hdr3 v1 against v2: the body 1.85 pt lower for the shadow on the
                // raised run alone, the reach 4 - 3 sin 45 = 1.88.)
                let raisedRun = s.baselineShift != nil
                s = s.copyWith(baselineShift: (s.baselineShift ?? 0) + above, ascentOverride: up, descentOverride: down, height: (up + down) * max(1, p.style.lineSpacing) / size,
                               leadingDistribution: .even, debugLabel: (s.debugLabel ?? "") + (raisedRun ? " shadow-line@\(allRaised ? above + below : above)" : " shadow-line"))
            }
        }
        // (A vertical page's column of East Asian text steps by the single line and 0.0425 of the size more: lab vpitch, Word's print of
        // Meiryo 1.990 em (ours 1.950), MS Mincho and Gothic 1.344 (1.297), Yu Mincho 1.7145 (1.673), at 8 to 24 pt.)
        if vertical, kind < 0, theme.wordRules, RichTextTheme.wordWindowsPages, p.style.lineHeightPoints == nil, pitch == nil,
           abs(p.style.lineSpacing - 1) < 0.005, let h = s.height, s.fontSize ?? 0 > 0.5 {
            RuleTrace.hit("vertical-plain-column-pitch-adds-0.0425-em")
            if let asc = s.ascentOverride, let desc = s.descentOverride, let size = s.fontSize {
                s = s.copyWith(ascentOverride: asc + 0.02125 * size, descentOverride: desc + 0.02125 * size, height: h + 0.0425)
            } else { s = s.copyWith(height: h + 0.0425) }
        }
        // (A run of tabs alone takes no line of its own in a paragraph of
        // other text: windows-1's lab `ttab`, zh-147bdae0's "四、承諾事項"
        // — its 16pt bold tab after 14pt text, at the line's end, mid-line
        // or 14pt, leaves the 1.5 lines 27.24 apart in Word's print, the
        // 14pt text's; the tab's line set the heading 9pt lower.)
        // (Text: not a drawing's anchor alone — zh-38d26944's red-headed
        // rule stands in a paragraph of a tab and its line's anchor,
        // whose line the tab holds.)
        if theme.wordRules, !text.isEmpty, text.allSatisfy({ $0 == "\t" }),
           p.text.contains(where: { !$0.isWhitespace && $0 != "\u{FFFC}" }), s.fontSize ?? 0 > 0.5 {
            s = s.copyWith(height: 0.01)
        }
        // (A floating drawing's anchor mark, in a paragraph that has other characters, gives its line no height of its
        // own: ba75c926's first paragraph holds two anchors, a 24pt bold run and a 16pt one, and a 20pt bold space; Word sets
        // the line by the space (baseline 56.2 for the next paragraph), ours by the 24pt anchor run (60.4).)
        if theme.wordRules, RichTextTheme.wordWindowsPages, !text.isEmpty, text.allSatisfy({ $0 == "\u{FFFC}" }),
           let key = run.inlineImage, let image = p.inlineImages[key], image.float != nil || image.textBox != nil,
           p.text.contains(where: { $0 != "\u{FFFC}" }), s.fontSize ?? 0 > 0.5 {
            s = s.copyWith(height: 0.01)
        }
        // (A run of spaces alone takes the line's height, not its own.)
        // (An en, an em and a four-per-em space are spaces to Word for
        // Windows as the plain one is, and give a line no height of
        // their own: lab `sp` (2026-10-30), rows of one 48pt space in a
        // 12pt row — U+0020, U+2002, U+2003 and U+2005 leave it 14.6pt,
        // in any colour, bold, highlighted or shaded; U+2000, U+2001,
        // U+2004, U+2006…200A, U+202F and a letter make it 56.7.
        // tdf153136 sets them so, 48pt, by the dozen.)
        let widerSpaces = theme.wordRules && RichTextTheme.wordWindowsPages
        let spaceLike: (Character) -> Bool = {
            $0 == " " || $0 == "\t" || $0 == "\u{3000}"
                || (widerSpaces && $0.unicodeScalars.count == 1 && [0x2002, 0x2003, 0x2005].contains($0.unicodeScalars.first!.value))
        }
        @inline(never) func _r0() {
        if let lineSize, !text.isEmpty, text.allSatisfy(spaceLike), let px = s.fontSize, px > 0.5 {
            let own = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
            if !lineSize.blank, kind != -2, !text.containsSubstring("\u{3000}"), !text.containsSubstring("\t") || (theme.wordRules && RichTextTheme.wordWindowsPages && own > lineSize.size + 0.01) {
                // (Beside other characters, spaces have no height
                // at all, whatever their face or size: lab `cap2`
                // (Word 16, 2026-10-17) — two 14pt or 20pt spaces
                // opening a 10.5pt 宋体 caption, in 仿宋_GB2312,
                // YaHei, Times or a face no one has, leave it one
                // pitch of the grid, and `cap3` 20pt spaces before,
                // within or after 10.5pt text one 10.5pt line.
                // Sized to the text in their own face they still
                // counted: YaHei's 10.5 is two pitches, and
                // zh-2a241df1's caption took a line more. A tab, a
                // no-break space and a glyph do count.)
                // (Shaded, they paint the shade: zh-1078e06f's grey blanks
                // after a signature line; a 0.01 box paints none.)
                if !RichLayout.shadeShows(run.highlight) || own > lineSize.size + 0.01 { s = s.copyWith(height: 0.01) }
            } else if own > lineSize.size + 0.01 || (lineSize.blank && own < lineSize.size - 0.01)
                        || (lineSize.blank && p.style.mark?.fontFamily != nil && p.style.mark?.fontFamily != run.fontFamily) {
                // (Same size, other face: a line of spaces alone is the mark's face's
                // in Word whatever the size — lab picm2: Malgun 11pt spaces under a
                // BatangChe 11pt mark are 10.4pt under the line above, not Malgun's 15.4.)
                var sized = run
                sized.fontSize = lineSize.size
                // (The mark's line in the mark's Latin face, where
                // the line is of spaces alone: zh-1eeb9f9a's "　"
                // cells, 9pt in 仿宋_GB2312 under a 12pt Times New
                // Roman mark, are one 15.6pt pitch in Word's print —
                // Times' 12pt line; in the run's 仿宋 (YaHei to
                // Word on a Mac) ours were two, and p11's row they
                // stand in went over whole where Word parts it.)
                if theme.wordRules, lineSize.blank {
                    // (A mark with no face of its own is drawn in the
                    // document default: kor-z22157092's Consolas
                    // " " line is the empty line's, not Consolas 10.)
                    sized.fontFamily = p.style.mark?.fontFamily
                }
                let r = theme.textStyle(for: sized, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                        eastAsian: kind < 0, gridPitch: pitch, characterClass: classed && kind >= 0 ? kind : nil,
                                        characterGrid: kind < 0 ? ideographGrid : latinGrid, scriptHidden: true)
                if let rs = r.fontSize, let rh = r.height, s.height != nil { s = s.copyWith(height: rs * rh / px) }
                else if s.height == nil, r.height == nil {
                    // (Single lines in a face of its own metrics
                    // have no height to scale: the spaces are set
                    // at the mark's size, as wide as their own —
                    // IllustrativeCases' line of 11pt spaces under
                    // an 8pt mark is 9.2pt in Word's print, and at
                    // 12.65 the last of three empty lines under a
                    // table went over the page.)
                    s = r.copyWith(letterSpacing: (r.letterSpacing ?? 0) + _spaceWidth(s) - _spaceWidth(r))
                }
            }
        }
        }
        _r0()
        if !fitBusy, fitGroup != nil, s.fontSize ?? 0 > 0.5, let f = fitSpacing() {
            let own = text.count == 1 && fitLastSingle && base + rawText.utf16.count >= fitLastEnd ? 0 : f
            s = s.copyWith(letterSpacing: kind == -2 ? (s.letterSpacing ?? 0) + own : own)
        }
        // (A mark of a right-to-left run is set in the complex-script face, not the Latin one its style names: the
        // line it stands on takes no height of its own. Tagged for _strut.)
        // (A symbol of a right-to-left run that the complex-script face lacks is drawn in Segoe UI Symbol, and its line takes that
        // face's height as in a left-to-right run: 842f1e's ✦ heading lines, 3.3pt short.)
        if run.rightToLeft, theme.wordRules, RichTextTheme.wordWindowsPages, kind >= 0, let px = s.fontSize, px > 0.5, s.height != nil,
           s.debugLabel?.lowercased().containsSubstring("segoe ui symbol") == true,
           !text.contains(where: { $0.isLetter || $0.isNumber }), text.unicodeScalars.contains(where: { $0.properties.generalCategory == .otherSymbol }) {
            var latinRun = run
            latinRun.rightToLeft = false
            let r = theme.textStyle(for: latinRun, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                    eastAsian: false, gridPitch: pitch, characterClass: nil, characterGrid: grid, scriptHidden: true)
            if let rs = r.fontSize, let rh = r.height, rs * rh / px > (s.height ?? 0) { s = s.copyWith(height: rs * rh / px); RuleTrace.hit("word-rtl-symbol-segoe-line-height") }
        }
        if run.rightToLeft, theme.wordRules, RichTextTheme.wordWindowsPages, !text.contains(where: { $0.isLetter || $0.isNumber }) { s = s.copyWith(debugLabel: (s.debugLabel ?? "") + " rtl-mark") }
        // (Word's `w:textAlignment` "top": each run stands on its own ascent below the line's top, so a smaller run sets higher
        // than the baseline a bigger one on its line shares: xd sa1 97666801's 12 pt "SIM" beside a 16 pt box glyph stands 3.9 pt
        // higher in Word's print than ours. The line's height is the bigger run's, unchanged.)
        if kind >= 0, _topLiftBig != nil, theme.wordRules, RichTextTheme.wordWindowsPages, p.style.lineHeightPoints == nil,
           p.style.eastAsian["w:textAlignment"] == "top", let size = s.fontSize, size > 0.5 {
            // (Only the size differs: the same face's ascent at the paragraph's biggest size against its own.)
            func sizePt(_ r: CharStyle) -> Double { r.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize }
            let fam = run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily
            let ratio = theme.faceResolver?(fam, false)?.baseline ?? 0.8
            let own = sizePt(run) * ratio
            // (The biggest run on THIS line, from the probe layout `_topLift`: Word stands each line's runs on that line's
            // own tallest run, not the paragraph's — xd 0815aa59's one 22 pt space lifts its own line only.)
            let most = (_topLiftBig ?? sizePt(run)) * ratio
            if most - own > 0.05 {
                RuleTrace.hit("word-top-aligned-runs-stand-on-their-own-ascent")
                s = s.copyWith(baselineShift: (s.baselineShift ?? 0) - (most - own) * theme.pixelsPerPoint * scale)
            }
        }
        if !fitBusy, !plainPiece, !latinNoScale { styles[kind] = s }
        return s
    }
    func zeroWidth(_ kind: Int) -> TextStyle {
        let s = style(kind < 0 ? 0 : kind).copyWith(letterSpacing: 0)
        return theme.wordRules && s.fontSize ?? 0 > 0.5 && !(kind >= 0 && latinFace?.setsMath == true) ? s.copyWith(height: 0.01) : s
    }
    func isArabic(_ c: Character) -> Bool { c.unicodeScalars.first.map { ArabicForms.isArabic($0.value) || $0.value == 0x200C } ?? false }
    func joinedScaled(_ word: Substring, _ s: TextStyle) -> TextStyle {
        // (Myanmar letters, word by word, at Myanmar Text's own advances: the stand-in has no Myanmar glyph and runs the line 12% wide.)
        if theme.wordRules, document.readFromFile, let px = s.fontSize, px > 0.5,
           word.unicodeScalars.contains(where: { $0.value >= 0x1000 && $0.value <= 0x109F }) {
            let table = s.fontWeight == .bold ? MyanmarAdvances.bold : MyanmarAdvances.regular
            if word.unicodeScalars.allSatisfy({ table[$0.value] != nil }) {
                let ems = word.unicodeScalars.reduce(0.0) { $0 + (table[$1.value] ?? 0) }
                let shaped = _wordWidth(s, String(word))
                RuleTrace.hit("word-myanmar-letters-at-myanmar-text-advances")
                return shaped > 0.01 ? s.copyWith(scaleX: ems * px / shaped) : s
            }
        }
        // (Sinhala letters, word by word, at Nirmala UI's advances summed per code point, split vowels from their parts.)
        if theme.wordRules, document.readFromFile, let px = s.fontSize, px > 0.5,
           word.unicodeScalars.contains(where: { $0.value >= 0xD80 && $0.value <= 0xDFF }), let ems = SinhalaAdvances.sum(word, bold: s.fontWeight == .bold) {
            let shaped = _wordWidth(s, String(word))
            RuleTrace.hit("word-sinhala-letters-at-nirmala-ui-advances")
            return shaped > 0.01 ? s.copyWith(scaleX: ems * px / shaped) : s
        }
        // (Ethiopic letters, word by word, at Nyala's own advances: the stand-in has no Ethiopic glyph and sets each at 0.75 em, where Nyala's run 0.35 to 1.03; a letter we have not read takes the median. Other characters of the word keep their own width.)
        if theme.wordRules, document.readFromFile, RichTextTheme.wordWindowsPages, let px = s.fontSize, px > 0.5,
           word.unicodeScalars.contains(where: { $0.value >= 0x1200 && $0.value <= 0x139F }) {
            var ems = 0.0
            var others = ""
            for u in word.unicodeScalars {
                if u.value >= 0x1200 && u.value <= 0x139F { ems += EthiopicAdvances.nyala[u.value] ?? EthiopicAdvances.median } else { others.unicodeScalars.append(u) }
            }
            let shaped = _wordWidth(s, String(word))
            let rest = others.isEmpty ? 0 : _wordWidth(s, others)
            RuleTrace.hit("word-ethiopic-letters-at-nyala-advances")
            return shaped > 0.01 ? s.copyWith(scaleX: (ems * px + rest) / shaped) : s
        }
        // (Hebrew, word by word, at the advances the face carries per letter: David's, from Word's prints. A run of underscores too: the Cambria stand-in's is 0.633 em where David's is 0.504, Word's 6.0pt at 12.)
        // (A number of a right-to-left run, digits and its separators, in a face that carries those advances too: FrankRuehl's 0.415 em digit in
        // xd 38d880e8's case number, where the Latin stand-in's 0.553 ran the line wider. Direction marks have no width.)
        // (The Hebrew-context table, with the punctuation and Latin around the letters, serves only words with a Hebrew letter or a number in a right-to-left run; an underscore line or Latin word in Arial keeps the stand-in's: lo-015dbec5.)
        let hebrewContext = word.unicodeScalars.contains(where: { $0.value >= 0x5D0 && $0.value <= 0x5EA }) || (joinedFace != nil && word.unicodeScalars.contains(where: { (0x30...0x39).contains($0.value) }))
        let numberInComplexFace = joinedFace != nil && word.unicodeScalars.contains(where: { (0x30...0x39).contains($0.value) })
        if let hebrewFace = joinedFace ?? complexFaceOfRun, numberInComplexFace || word.unicodeScalars.contains(where: { $0.value >= 0x5D0 && $0.value <= 0x5EA }) || (word.unicodeScalars.contains(where: { $0.value == 0x5F }) && word.unicodeScalars.allSatisfy({ $0.value == 0x5F || $0.value == 0x20 })), let px = s.fontSize, px > 0.5,
           let table = s.fontWeight == .bold ? ((hebrewContext ? hebrewFace.boldHebrewAdvances : nil) ?? hebrewFace.boldOtherAdvances) : ((hebrewContext ? hebrewFace.hebrewAdvances : nil) ?? hebrewFace.otherAdvances),
           word.unicodeScalars.allSatisfy({ table[$0.value] != nil || $0.value == 0x200E || $0.value == 0x200F }) {
            let ems = word.unicodeScalars.reduce(0.0) { $0 + (table[$1.value] ?? 0) }
            let shaped = _wordWidth(s, String(word))
            RuleTrace.hit("word-hebrew-face-own-advances")
            return shaped > 0.01 ? s.copyWith(scaleX: ems * px / shaped) : s
        }
        guard let joinedFace, let first = word.first, isArabic(first), first != "\u{200C}", word.allSatisfy(isArabic),
              let table = s.fontWeight == .bold ? joinedFace.boldJoinedAdvances : joinedFace.joinedAdvances, let px = s.fontSize, px > 0.5
        else { return s }
        // (A word the face's shaped table holds: its own advance, not the sum over letters; xb fas-3a9879's title.)
        if let words = s.fontWeight == .bold ? joinedFace.boldJoinedWords : joinedFace.joinedWords, let e = words[String(word)] {
            let shaped = _wordWidth(s, String(word))
            RuleTrace.hit("word-rtl-sakkal-shaped-word-advance")
            return shaped > 0.01 ? s.copyWith(scaleX: e * px / shaped) : s
        }
        var ems = 0.0, shaped = 0.0
        // (The mark is a grapheme extender: it is one Character with the
        // letter before it, so the word is cut by its scalars.)
        for part in word.unicodeScalars.split(separator: "\u{200C}", omittingEmptySubsequences: true) {
            // (A piece at the start or end of the run joins the letter beyond it.)
            let atStart = part.startIndex == word.unicodeScalars.startIndex, atEnd = part.endIndex == word.unicodeScalars.endIndex
            var before: UInt32? = nil
            if atStart, word.startIndex == text.startIndex, base > 0, base - 1 < p.text.utf16.count {
                let i = p.text.utf16.index(p.text.utf16.startIndex, offsetBy: base - 1)
                before = p.text.unicodeScalars[i].value
            }
            let after: UInt32? = atEnd && word.endIndex == text.endIndex ? next?.unicodeScalars.first?.value : nil
            let clusters = s.fontWeight == .bold ? joinedFace.boldJoinedClusters : joinedFace.joinedClusters
            guard let e = ArabicForms.width(part.map { $0.value }, table, before: before, after: after, clusters: clusters) else { return s }
            ems += e
            shaped += _wordWidth(s, String(String.UnicodeScalarView(part)))
        }
        return shaped > 0.01 ? s.copyWith(scaleX: ems * px / shaped) : s
    }
    func flush(_ end: Substring.Index) {
        guard let kind = current, start < end else { return }
        if yuOfMissingHangul, text[start ..< end].unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x250 }),
           let y = RichLayout._yuLatinStyle(text[start ..< end], base: joinedScaled(text[start ..< end], style(kind))) {
            RuleTrace.hit("word-missing-hangul-face-latin-takes-yu-gothic-advances")
            spans.append(contentsOf: capped(text[start ..< end], run, y))
            start = end
            return
        }
        // (A Hebrew word a line break (w:br) runs through: each part at the face's own advances, the break between them as it is; the whole
        // piece skipped the table for the break and kept the stand-in's widths: xd 7d58f74e and fcd0d58c.)
        if RichTextTheme.wordWindowsPages, joinedFace != nil, text[start ..< end].unicodeScalars.contains(where: { $0.value == 0x0A }),
           text[start ..< end].unicodeScalars.contains(where: { $0.value >= 0x5D0 && $0.value <= 0x5EA }) {
            let base = style(kind)
            var parts: [Substring] = []
            var from = start
            var i = start
            while i < end {
                if text[i] == "\n" { if from < i { parts.append(text[from ..< i]) }; parts.append(text[i ... i]); from = text.index(after: i) }
                i = text.index(after: i)
            }
            if from < end { parts.append(text[from ..< end]) }
            for p in parts {
                if p == "\n" { spans.append(TextSpan(text: "\n", style: zeroWidth(kind))) }
                else { spans.append(contentsOf: capped(p, run, joinedScaled(p, base))) }
            }
            RuleTrace.hit("word-hebrew-word-split-at-break")
            start = end
            return
        }
        if joinedFace != nil, text[start ..< end].unicodeScalars.contains(where: { $0.value == 0x200C }) {
            // (The mark at no width, between two words each at its
            // own: Word's print has it so, the stand-in 3pt.)
            let word = text[start ..< end]
            let base = style(kind)
            var part = String.UnicodeScalarView()
            func put() {
                guard !part.isEmpty else { return }
                let piece = String(part)
                spans.append(contentsOf: capped(Substring(piece), run, joinedScaled(Substring(piece), base)))
                part = String.UnicodeScalarView()
            }
            for u in word.unicodeScalars {
                if u.value == 0x200C {
                    put()
                    let alone = TextPainter(text: TextSpan(text: "\u{200C}", style: base), textDirection: .ltr)
                    alone.layout(minWidth: 0, maxWidth: 100_000)
                    let own = alone.width
                    alone.dispose()
                    spans.append(TextSpan(text: "\u{200C}", style: base.copyWith(letterSpacing: (base.letterSpacing ?? 0) - own)))
                } else { part.append(u) }
            }
            put()
            start = end
            return
        }
        // (A Tamil run whose complex face Windows lacks (Arial Unicode MS): its Latin, digits and punctuation Word draws in Leelawadee UI.)
        let leelawadeeLatin = (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms"
        if kind >= 0, indic?.face == "leelawadee ui", text[start ..< end].unicodeScalars.contains(where: { ($0.value >= 0x0E01 && $0.value <= 0x0E5B) || ($0.value >= 0x0E81 && $0.value <= 0x0EDF) }) {
            // (Thai without w:cs, word by word, at Leelawadee UI's advances: `ThaiAdvances`.)
            let base = style(kind)
            var wordStart = start
            func putWord(_ a: Substring.Index, _ b: Substring.Index) {
                guard a < b else { return }
                let w = text[a ..< b]
                var st = base
                if let px = base.fontSize, px > 0.5, let split = ThaiAdvances.split(w, bold: base.fontWeight == .bold) {
                    // (As spacing, not a scale: the line breaking measures it. Spread over the glyphs the engine draws.)
                    func measure(_ ls: Double) -> Double {
                        let t = TextPainter(text: TextSpan(text: String(w), style: base.copyWith(letterSpacing: ls)), textDirection: .ltr)
                        t.layout(minWidth: 0, maxWidth: 100_000)
                        defer { t.dispose() }
                        return t.width
                    }
                    let w0 = measure(0)
                    let n = max(1, Int((measure(10) - w0) / 10 + 0.5))
                    // (A character the table lacks keeps the stand-in's own width.)
                    var other = 0.0
                    if split.rest {
                        let t = TextPainter(text: TextSpan(text: split.known, style: base.copyWith(letterSpacing: 0)), textDirection: .ltr)
                        t.layout(minWidth: 0, maxWidth: 100_000)
                        other = w0 - t.width
                        t.dispose()
                    }
                    if w0 > 0.01 { st = base.copyWith(letterSpacing: (base.letterSpacing ?? 0) + (split.ems * px + other - w0) / Double(n)) }
                }
                spans.append(contentsOf: capped(w, run, st))
            }
            var k = start
            while k < end {
                if text[k] == " " || text[k] == "\u{00A0}" {
                    putWord(wordStart, k)
                    spans.append(contentsOf: capped(text[k ..< text.index(after: k)], run, base))
                    wordStart = text.index(after: k)
                }
                k = text.index(after: k)
            }
            putWord(wordStart, end)
            start = end
            return
        }
        if kind >= 0, indic?.face == "raavi", theme.wordRules, RichTextTheme.wordWindowsPages, text[start ..< end].unicodeScalars.contains(where: { (0x0A01 ... 0x0A76).contains($0.value) }) {
            // (Punjabi set in Raavi, word by word, at the face's own advances: `RaaviAdvances`. The stand-in's Gurmukhi is 8 percent wider.)
            let base = style(kind).copyWith(scaleX: 1)
            var wordStart = start
            func putWord(_ a: Substring.Index, _ b: Substring.Index) {
                guard a < b else { return }
                let w = text[a ..< b]
                var st = base
                if let px = base.fontSize, px > 0.5, let split = RaaviAdvances.split(w, bold: base.fontWeight == .bold) {
                    func measure(_ ls: Double) -> Double {
                        let t = TextPainter(text: TextSpan(text: String(w), style: base.copyWith(letterSpacing: ls)), textDirection: .ltr)
                        t.layout(minWidth: 0, maxWidth: 100_000)
                        defer { t.dispose() }
                        return t.width
                    }
                    let w0 = measure(0)
                    let n = max(1, Int((measure(10) - w0) / 10 + 0.5))
                    var other = 0.0
                    if split.rest {
                        let t = TextPainter(text: TextSpan(text: split.known, style: base.copyWith(letterSpacing: 0)), textDirection: .ltr)
                        t.layout(minWidth: 0, maxWidth: 100_000)
                        other = w0 - t.width
                        t.dispose()
                    }
                    if w0 > 0.01 {
                        RuleTrace.hit("word-raavi-words-at-the-faces-own-advances")
                        st = base.copyWith(letterSpacing: (base.letterSpacing ?? 0) + (split.ems * px + other - w0) / Double(n))
                    }
                }
                spans.append(contentsOf: capped(w, run, st))
            }
            var k = start
            while k < end {
                if text[k] == " " || text[k] == "\u{00A0}" {
                    putWord(wordStart, k)
                    spans.append(contentsOf: capped(text[k ..< text.index(after: k)], run, base))
                    wordStart = text.index(after: k)
                }
                k = text.index(after: k)
            }
            putWord(wordStart, end)
            start = end
            return
        }
        if kind >= 0, indic?.face == "nirmala ui" || indic?.face == "vijaya", text[start ..< end].unicodeScalars.contains(where: { RichLayout._tamil.contains($0.value) }) {
            // (Tamil, word by word, at the widths of Nirmala UI's code points: `TamilAdvances`.)
            let base = style(kind)
            let tamilCs = run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? ""
            let spaceInMangal = RichLayout._markInMangal(tamilCs, text[start ..< end])
            var wordStart = start
            func putWord(_ a: Substring.Index, _ b: Substring.Index) {
                guard a < b else { return }
                let w = text[a ..< b]
                var st = base
                if let px = base.fontSize, px > 0.5, let split = TamilAdvances.split(w, bold: base.fontWeight == .bold, vijaya: indic?.face == "vijaya", leelawadee: leelawadeeLatin) {
                    // (As spacing, not a scale: the line breaking measures it. Spread over the glyphs the engine draws.)
                    func measure(_ ls: Double) -> Double {
                        let t = TextPainter(text: TextSpan(text: String(w), style: base.copyWith(letterSpacing: ls)), textDirection: .ltr)
                        t.layout(minWidth: 0, maxWidth: 100_000)
                        defer { t.dispose() }
                        return t.width
                    }
                    let w0 = measure(0)
                    let n = max(1, Int((measure(10) - w0) / 10 + 0.5))
                    // (A character the table lacks keeps the stand-in's own width.)
                    var other = 0.0
                    if split.rest {
                        let t = TextPainter(text: TextSpan(text: split.known, style: base.copyWith(letterSpacing: 0)), textDirection: .ltr)
                        t.layout(minWidth: 0, maxWidth: 100_000)
                        other = w0 - t.width
                        t.dispose()
                    }
                    if w0 > 0.01 { st = base.copyWith(letterSpacing: (base.letterSpacing ?? 0) + (split.ems * px + other - w0) / Double(n)) }
                }
                spans.append(contentsOf: capped(w, run, st))
            }
            var k = start
            while k < end {
                if text[k] == " " || text[k] == "\u{00A0}" {
                    putWord(wordStart, k)
                    // A space between Tamil words set in Noto Sans Tamil (a face Windows lacks): Word draws it in Mangal, 0.5 em (6.0 pt at 12 pt)
                    // where the stand-in's Latin space is 2.7 (xd c016493b: its centred lines start 17 pt right of Word's).
                    if spaceInMangal, text[k] == " ", let px0 = base.fontSize, px0 > 0.5 {
                        RuleTrace.hit("word-noto-tamil-space-is-mangal-half-em")
                        spans.append(contentsOf: capped(text[k ..< text.index(after: k)], run, _indicSpaceStyle(base: base, spaceEm: 0.5, unit: px0)))
                    } else {
                        spans.append(contentsOf: capped(text[k ..< text.index(after: k)], run, base))
                    }
                    wordStart = text.index(after: k)
                }
                k = text.index(after: k)
            }
            putWord(wordStart, end)
            start = end
            return
        }
        // (A word the fit's cut on a neighbouring space splits out of its run is still the run's: the cut makes a run of every space and
        // word, and a word alone has no Latin to open this branch, so it fell to the flat scale and the engine found room the fit never
        // counted. Only where there is a cut: a run of one word that is its own run, as Word has it, is as it was. f0001d05.)
        // (The fitter's own probe has no cut either, but measures a word segment alone: it takes the whole run's text too, so a Kokila word
        // is fitted at the table width the final pass draws it at. xd d760f1e5 220 to 229 matched lines.)
        if kind >= 0, indic?.face == "kokila", kokilaLatin, let px = style(kind).fontSize, px > 0.5, let m = RichLayout._indicLines["kokila"],
           (adjust.isEmpty && !fitProbe ? text[start ..< end] : text[...]).unicodeScalars.contains(where: { $0.value < 0x250 || $0.value == 0x2026 || $0.value == 0x201C || $0.value == 0x201D }) {
            // (Kokila's own Latin, digits and space: `KokilaLatin`; Devanagari stays on the flat scale.)
            let base = style(kind)
            var i = start
            func isLatin(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { $0.value < 0x250 || $0.value == 0x2026 || $0.value == 0x201C || $0.value == 0x201D } }
            while i < end {
                var j = i
                let latin = isLatin(text[i])
                while j < end, isLatin(text[j]) == latin { j = text.index(after: j) }
                let seg = text[i ..< j]
                if latin {
                    let st = _kokilaLatinStyle(seg, base: base, px: px)
                    spans.append(contentsOf: capped(seg, run, st))
                } else {
                    // (Kokila's own cluster widths where the table has the word: `KokilaAdvances`.)
                    let kBold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
                    let kItalic = run.italic || ((named?.char.italic ?? false) && !run.off.contains(.italic))
                    let aSize: Double = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                    let aW: Double = wScale > 0.01 ? wScale : 1
                    let authored: Double = aSize * theme.pixelsPerPoint * scale * aW
                    if authored > 0.5, let fitted = _clusterFitted(seg, base: base, authored: authored, table: KokilaAdvances.table(bold: kBold, italic: kItalic), flatScale: RichLayout._indicScale["kokila"]?["D"] ?? 1) {
                        spans.append(contentsOf: capped(seg, run, fitted.style))
                    } else {
                        spans.append(contentsOf: capped(seg, run, joinedScaled(seg, base)))
                    }
                }
                i = j
            }
            start = end
            return
        }
        if kind >= 0, let face = indic?.face, let spaceEm = (face == "vrinda" && (run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold)))) ? 0.3125 : RichLayout._indicSpace[face], let px = style(kind).fontSize, px > 0.5,
           face == "mangal" || (adjust.isEmpty ? text[start ..< end] : text[...]).contains(Character(" ")) || text[start ..< end].contains(Character("\u{00A0}")) {
            // (Word's space is the face's own: Mangal 0.5 em against the stand-in's 0.26; the prints' gap between words, 5.5 pt against our 3.5 at 11 pt.)
            let runOffset = base
            let base = style(kind)
            var spaceStyle: TextStyle? = nil
            var wordStart = start, k = start
            // (Mangal's own widths, Word's print: the space half an em and each cluster at its fitted advance, `MangalAdvances`, on the
            // authored size, not the stand-in's enlarged one.)
            let mangalBold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
            let mangalRegular = face == "mangal"
            // (Mangal's table is em of the size Word WRITES, on its 0.12 pt grid (11 pt is 11.04): at 600 dpi it sets the face at a whole ppem, so a 11 pt line
            // is 0.36% wider than exact. 9baed400's "…सम्पन्न भएको।" needs 7.6 pt of squeeze at 11.04, 6.75 at 11.0, and Word refused it.)
            let mSize: Double = RichLayout._wordGridSize(run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize, snap: mangalRegular && theme.wordRules && RichTextTheme.wordWindowsPages) 
            let mW: Double = wScale > 0.01 ? wScale : 1
            let authored: Double = mSize * theme.pixelsPerPoint * scale * mW
            func putWord(_ a: Substring.Index, _ b: Substring.Index) {
                guard a < b else { return }
                let w = text[a ..< b]
                if mangalRegular, authored > 0.5, let split = MangalAdvances.split(w, bold: mangalBold, stacked: bidiLanguage == "sa-IN") {
                    let flat = base.copyWith(scaleX: 1)
                    func measure(_ s: String, _ ls: Double) -> Double {
                        let t = TextPainter(text: TextSpan(text: s, style: flat.copyWith(letterSpacing: ls)), textDirection: .ltr)
                        t.layout(minWidth: 0, maxWidth: 100_000)
                        defer { t.dispose() }
                        return t.width
                    }
                    let w0 = measure(String(w), 0)
                    if w0 > 0.01 {
                        let n = max(1, Int((measure(String(w), 10) - w0) / 10 + 0.5))
                        let other = split.rest ? (w0 - measure(split.known, 0)) * (RichLayout._indicScale["mangal"]?["D"] ?? 1) : 0
                        spans.append(contentsOf: capped(w, run, flat.copyWith(letterSpacing: (flat.letterSpacing ?? 0) + (split.ems * authored + other - w0) / Double(n))))
                        return
                    }
                }
                // (A run whose ascii face is Vrinda too draws its Latin in Vrinda: its own advances, `VrindaAdvances`, at the authored size.)
                if face == "vrinda", theme.wordRules, RichTextTheme.wordWindowsPages, authored > 0.5,
                   (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "vrinda",
                   w.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value < 0x7F }) {
                    let vTable = (run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))) ? VrindaAdvances.bold : VrindaAdvances.regular
                    if let fitted = _clusterFitted(w, base: base, authored: authored, table: vTable, flatScale: 1, conjunctRatio: nil, block: 0x980) {
                        RuleTrace.hit("word-vrinda-latin-own-advances")
                        spans.append(contentsOf: capped(w, run, fitted.style))
                        return
                    }
                }
                // (A Latin word of a run that names its own Latin face is that face's, not stretched by the Indic scale, as in the Nirmala path above:
                // dx2 88e26672's "(Police Department)", Arial 10 pt, 30.5 pt in Word.)
                if mangalRegular, run.fontFamily != nil, !w.unicodeScalars.contains(where: { $0.value >= 0x0900 && $0.value < 0x0E00 || $0.value == 0xA0 }),
                   w.contains(where: { $0.isLetter || $0.isNumber }) {
                    latinNoScale = true
                    let plain = style(kind)
                    latinNoScale = false
                    spans.append(contentsOf: capped(w, run, joinedScaled(w, plain)))
                    return
                }
                spans.append(contentsOf: capped(w, run, joinedScaled(w, base)))
            }
            while k < end {
                if text[k] == "\t", theme.wordRules {
                    // (A tab is no part of a word: inside one, its stop was lost to the word's fitted spacing and the text after it stood
                    // at the tab's own few points, not at the hanging indent: xd 6be5dbc9's "३.<tab>संस्थाको".)
                    putWord(wordStart, k)
                    let tabAdjust = adjust[runOffset + text.utf16.distance(from: text.startIndex, to: k)] ?? 0
                    if tabAdjust == 0 {
                        spans.append(TextSpan(text: "\t", style: base))
                    } else {
                        spans.append(TextSpan(text: "\u{00A0}", style: base.copyWith(letterSpacing: (base.letterSpacing ?? 0) + tabAdjust)))
                    }
                    wordStart = text.index(after: k)
                } else if text[k] == " " || text[k] == "\u{00A0}" {
                    putWord(wordStart, k)
                    if spaceStyle == nil {
                        // (A run whose own Latin face is Arial, drawn in Mangal only because the document's first Devanagari run names Mangal: Word's space
                        // is still Arial's, 0.278 em (2.8 pt at 10 pt), not Mangal's half em: dx2 88e26672, the gap between words 2.9 pt.)
                        let ownFace = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
                        let sp = mangalRegular && document.devanagariFirstRunMangal && ownFace == "arial" && (run.fontFamily ?? "").trimmingWhitespace().lowercased() == "arial" ? 0.2778 : spaceEm
                        spaceStyle = _indicSpaceStyle(base: base, spaceEm: sp, unit: mangalRegular ? authored : px)
                    }
                    spans.append(contentsOf: capped(text[k ..< text.index(after: k)], run, spaceStyle ?? base))
                    wordStart = text.index(after: k)
                }
                k = text.index(after: k)
            }
            putWord(wordStart, end)
            start = end
            return
        }
        if kind >= 0, indic?.face == "shonar bangla", text[start ..< end].unicodeScalars.contains(where: { ($0.value >= 0x980 && $0.value <= 0x9FF) || ((run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "shonar bangla" && $0.value < 0x980 && $0 != " " && ShonarAdvances.regular[String($0)] != nil) || (_shonarLatinRunFace(run, named, document, p.text) != nil && $0.value < 0x980 && $0 != " " && ShonarAdvances.regular[String($0)] != nil) || (!(run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))) && ShonarAdvances.regular[String($0)] != nil && $0.value < 0x980 && $0 != " ") }) {
            let shBold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
            let shTable = shBold ? ShonarAdvances.bold : ShonarAdvances.regular
            // (Shonar Bangla's own Bengali cluster widths, word by word: `ShonarAdvances`.)
            let shSize: Double = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
            let shW: Double = wScale > 0.01 ? wScale : 1
            // (A character scale w:w widens every cluster by it: dx2 3f7da49c's 105% title, word 1 is 85.8 pt in Word, 81.8 unscaled.)
            let authored: Double = shSize * theme.pixelsPerPoint * scale * shW
            let base = style(kind)
            for (piece, isIndic) in RichLayout._splitIndicLatin(text[start ..< end]) {
                                        if isIndic, authored > 0.5 {
                    var ws = piece.startIndex
                    while ws < piece.endIndex {
                        var we = ws
                        let sp = piece[ws] == " "
                        while we < piece.endIndex, (piece[we] == " ") == sp { we = piece.index(after: we) }
                        let seg = piece[ws ..< we]
                        if !sp, let fitted = _clusterFitted(seg, base: base, authored: authored, table: shTable, flatScale: RichLayout._indicScale["shonar bangla"]?["B"] ?? 1, conjunctRatio: nil, block: 0x980) {
                            spans.append(contentsOf: capped(seg, run, fitted.style))
                        } else if sp, let spaced = _shonarSpaced(seg, base: base, authored: authored) {
                            // (Word's own space, 0.2065 em from the print's subset, at the authored size: the old flat scale also shrank it to 2.27 pt of 2.88.)
                            spans.append(contentsOf: capped(seg, run, spaced))
                        } else {
                            spans.append(contentsOf: capped(seg, run, joinedScaled(seg, style(kind))))
                        }
                        ws = we
                    }
                } else if authored > 0.5, piece.allSatisfy({ $0 == " " }), let spaced = _shonarSpaced(piece, base: base, authored: authored) {
                    spans.append(contentsOf: capped(piece, run, spaced))
                } else if authored > 0.5, piece.firstIndex(of: " ") != nil, piece.unicodeScalars.allSatisfy({ $0 == " " || (shTable[String($0)] != nil && $0.value < 0x980) }) {
                    // (Latin words and the spaces between them, each in Shonar's own advances: the Latin of a run in Shonar Bangla, dx2 3f7da49c ": [Insert Project Name]".)
                    var ws = piece.startIndex
                    while ws < piece.endIndex {
                        var we = ws
                        let sp = piece[ws] == " "
                        while we < piece.endIndex, (piece[we] == " ") == sp { we = piece.index(after: we) }
                        let seg = piece[ws ..< we]
                        if !sp, let fitted = _clusterFitted(seg, base: base, authored: authored, table: shTable, flatScale: 1, conjunctRatio: nil, block: 0x980) {
                            spans.append(contentsOf: capped(seg, run, fitted.style))
                        } else if sp, let spaced = _shonarSpaced(seg, base: base, authored: authored) {
                            spans.append(contentsOf: capped(seg, run, spaced))
                        } else {
                            spans.append(contentsOf: capped(seg, run, joinedScaled(seg, style(kind))))
                        }
                        ws = we
                    }
                } else if authored > 0.5, piece.unicodeScalars.allSatisfy({ shTable[String($0)] != nil && $0.value < 0x980 }), let fitted = _clusterFitted(piece, base: base, authored: authored, table: shTable, flatScale: 1, conjunctRatio: nil, block: 0x980) {
                    // (Each stretch ending in a hyphen fitted on its own: one letter spacing over a whole URL leaves the width of its first part short of Shonar's, so
                    // dx2 3f7da49c's "...#credit-and-justice-" fitted a line it overruns in Word, whose limit is 5.45 pt in from the margin.)
                    var cs = piece.startIndex
                    var parts: [Substring] = []
                    while cs < piece.endIndex {
                        var ce = cs
                        while ce < piece.endIndex { let c = piece[ce]; ce = piece.index(after: ce); if c == "-", ce < piece.endIndex, piece[ce] != "-" { break } }
                        parts.append(piece[cs ..< ce]); cs = ce
                    }
                    if parts.count > 1, parts.allSatisfy({ _clusterFitted($0, base: base, authored: authored, table: shTable, flatScale: 1, conjunctRatio: nil, block: 0x980) != nil }) {
                        for part in parts { spans.append(contentsOf: capped(part, run, _clusterFitted(part, base: base, authored: authored, table: shTable, flatScale: 1, conjunctRatio: nil, block: 0x980)!.style)) }
                    } else {
                        spans.append(contentsOf: capped(piece, run, fitted.style))
                    }
                } else {
                    spans.append(contentsOf: capped(piece, run, joinedScaled(piece, style(kind))))
                }
            }
            start = end
            return
        }
        if kind >= 0, indic?.face == "nirmala ui", !(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased().hasPrefix("nirmala ui "), text[start ..< end].unicodeScalars.contains(where: { ($0.value >= 0x900 && $0.value <= 0x9FF) || ($0.value >= 0xA00 && $0.value <= 0xAFF) }),
           !text[start ..< end].unicodeScalars.contains(where: { RichLayout._tamil.contains($0.value) }) {
            // (Nirmala UI's own Devanagari cluster widths, word by word: `NirmalaAdvances`.)
            let nBold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
            let aSize: Double = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
            let aW: Double = wScale > 0.01 ? wScale : 1
            let authored: Double = aSize * theme.pixelsPerPoint * scale * aW
            let base = style(kind)
            for (piece, isIndic) in RichLayout._splitIndicLatin(text[start ..< end]) {
                                        if isIndic, authored > 0.5 {
                    // (Each word on its own, so the fitted letter spacing never reaches the spaces between words.)
                    var ws = piece.startIndex
                    while ws < piece.endIndex {
                        var we = ws
                        // (In a Bengali face Windows lacks, a no-break space beside a space is drawn in Mangal as the space is: xd 73caaeda's "এবং" + SP + NBSP + "মঙ্গোল", two 6.0 pt spaces in Word, 8.0 pt here.)
                        let missingBn = RichLayout._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") != nil
                        let isGap: (Character) -> Bool = { $0 == " " || (missingBn && $0 == "\u{00A0}") }
                        let sp = isGap(piece[ws])
                        while we < piece.endIndex, isGap(piece[we]) == sp { we = piece.index(after: we) }
                        let seg = piece[ws ..< we]
                        if !sp, let fitted = _clusterFitted(seg, base: base, authored: authored, table: NirmalaAdvances.table(bold: nBold), flatScale: 1, conjunctRatio: nil, block: seg.unicodeScalars.first(where: { $0.value >= 0x900 && $0.value < 0xB00 }).map { $0.value & ~0x7F } ?? 0x900, lowVowelsZero: !nBold, spaceMarks: true) {
                            spans.append(contentsOf: capped(seg, run, fitted.style))
                        } else if sp, authored > 0.5, let em = RichLayout._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") {
                            // (A Bengali face Windows lacks: Word draws the space in Mangal, half an em, not the stand-in's 0.26: xd 73caaeda, 6.0 pt at 12 pt.)
                            RuleTrace.hit("word-missing-bengali-face-space-is-mangal-half-em")
                            spans.append(contentsOf: capped(seg, run, _indicSpaceStyle(base: base, spaceEm: em, unit: authored)))
                        } else {
                            spans.append(contentsOf: capped(seg, run, leelawadeeLatin ? RichLayout._arialUnicodeLatin(seg, base: joinedScaled(seg, style(kind))) : joinedScaled(seg, style(kind))))
                        }
                        ws = we
                    }
                } else {
                    plainPiece = !isIndic
                    // (Latin letters and digits of a run that names its own Latin face are that face's, not stretched by the Indic scale:
                    // d912c25b's "(COVID-19)", Calibri 12, 54.7 pt in Word, 57.9 here.)
                    latinNoScale = !isIndic && latinFaceNamed && p.text.unicodeScalars.contains(where: { ($0.value >= 0x905 && $0.value <= 0x939) || ($0.value >= 0xA05 && $0.value <= 0xA39) }) && (piece.contains(where: { $0.isLetter || $0.isNumber }) || piece.unicodeScalars.contains(where: { $0.value > 0x20 }) && piece.unicodeScalars.allSatisfy({ $0.value < 0x80 && $0.value != 0x20 })) && !piece.unicodeScalars.contains(where: { $0.value == 0xA0 })
                    // (A space between Devanagari words in a run whose ascii face is a Windows Latin face (Calibri, Arial): Word draws it in that face (Hindi only: the Gujarati table is not re-measured and b785c95e's lines were level only by luck) at the
                    // run's size, 0.2256 em in Calibri; the Indic stretch (scaleX) belongs to the Devanagari glyphs only. d912c25b: 2.94 pt here, 2.76 in Word. The same for the ASCII marks (not the spaces: those follow the rule above for every Windows face) of a run that names, itself, a Latin face whose Windows metrics we hold (`WordWindowsFaces.metricsHeld`; PROVISIONAL: the stand-in's advances are used, not the face's own, so only the Indic stretch is dropped); a theme-derived or Aptos run drew its marks wide (xd 77d6ca49 17.5 to 4.5): ", " "-" ". " drawn at 12.48 here against Calibri's 12.0, 0.8 pt over one line: d912c25b p2 "...एक यह".)
                    let asciiFace = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
                    latinNoScale = latinNoScale || !isIndic && theme.wordRules && RichTextTheme.wordWindowsPages && !piece.isEmpty && (piece.allSatisfy({ $0 == " " }) || run.fontFamily != nil && WordWindowsFaces.metricsHeld.contains(asciiFace) && piece.unicodeScalars.allSatisfy({ $0.value < 0x80 && !$0.properties.isAlphabetic && !($0.value >= 0x30 && $0.value <= 0x39) })) && p.text.unicodeScalars.contains(where: { ($0.value >= 0x905 && $0.value <= 0x939) || ($0.value >= 0xA05 && $0.value <= 0xA39) }) && !asciiFace.isEmpty && !asciiFace.hasPrefix("nirmala ui") && WordWindowsFaces.names.contains(asciiFace)
                    let st = style(kind)
                    latinNoScale = false
                    plainPiece = false
                    if !isIndic, authored > 0.5, theme.wordRules, RichTextTheme.wordWindowsPages, piece.allSatisfy({ $0 == " " }), (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased().hasPrefix("nirmala ui"), RichLayout._splitIndicLatin(text[start ..< end]).contains(where: { $0.1 }) {
                        // (Spaces between the Devanagari words of a Nirmala UI run are Nirmala's own when the run's Latin (ascii) face is Nirmala too, 0.2739 em (bold 0.2759; in a run whose ascii face is Arial Word draws the space in Arial, 0.28 em: dx2 b785c95e, xd 1116b68d; lab/metrics/Nirmala_UI*.tsv, lab nirpitch3: Word 3.02 pt at 11 pt, the stand-in's 2.62).)
                        RuleTrace.hit("word-nirmala-space-own-advance")
                        spans.append(contentsOf: capped(piece, run, _indicSpaceStyle(base: st, spaceEm: nBold ? 0.2759 : 0.2739, unit: authored)))
                        continue
                    }
                    // (Spaces between the Bengali words of a run in a face Windows lacks (SolaimanLipi, Nikosh): Word draws them in Mangal, half an em, not the
                    // stand-in's quarter: xd 73caaeda, 6.0 pt at 12 pt, so Word's first line breaks 10 characters earlier than ours did.)
                    if !isIndic, authored > 0.5, theme.wordRules, RichTextTheme.wordWindowsPages, !piece.isEmpty, piece.allSatisfy({ $0 == " " || $0 == "\u{00A0}" }),
                       let em = RichLayout._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? ""),
                       p.text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF && $0.properties.isAlphabetic }) {
                        RuleTrace.hit("word-missing-bengali-face-space-between-words-is-mangal-half-em")
                        // (And it lifts the line to Mangal's 1.241 + 0.438 em as a mark does: the line of letters and spaces alone steps 20.2 in Word, 16 in ours.)
                        if !_isSolaimanLipi(run, named, document), devanagariStyles["mangal"] == nil, let m = RichLayout._indicLines["mangal"] {
                            devanagariStyles["mangal"] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: m.0, descent: m.1)
                        }
                        let spaceBase = !_isSolaimanLipi(run, named, document) ? (devanagariStyles["mangal"].flatMap { $0 } ?? st) : st
                        spans.append(contentsOf: capped(piece, run, _indicSpaceStyle(base: spaceBase, spaceEm: em, unit: authored)))
                        continue
                    }
                    spans.append(contentsOf: capped(piece, run, leelawadeeLatin ? RichLayout._arialUnicodeLatin(piece, base: joinedScaled(piece, st)) : joinedScaled(piece, st)))
                }
            }
            start = end
            return
        }
        if kind >= 0, indic?.face == "nirmala ui", RichLayout._splitIndicLatin(text[start ..< end]).count > 1 {
            // (Word builds each line from the tallest ascent and the deepest descent of the faces on it: the Latin, digits, spaces
            // and marks between Nirmala UI's words are Arial's and carry no Nirmala line of their own.)
            for (piece, isIndic) in RichLayout._splitIndicLatin(text[start ..< end]) {
                                        plainPiece = !isIndic
                latinNoScale = !isIndic && latinFaceNamed && p.text.unicodeScalars.contains(where: { ($0.value >= 0x905 && $0.value <= 0x939) || ($0.value >= 0xA05 && $0.value <= 0xA39) }) && piece.contains(where: { $0.isLetter || $0.isNumber }) && !piece.unicodeScalars.contains(where: { $0.value == 0xA0 })
                let st = style(kind)
                plainPiece = false
                latinNoScale = false
                spans.append(contentsOf: capped(piece, run, joinedScaled(piece, st)))
            }
            start = end
            return
        }
        // (A space in a right-to-left run whose face is Sakkal Majalla: Word's print draws it at the face's own 0.151 em, where
        // the stand-in's Latin space is 0.22; xb fas-3a9879's title, 7 spaces, 18 pt too wide.)
        if let em = joinedFace?.joinedSpaceEm, text[start ..< end].allSatisfy({ $0 == " " }), let px = style(kind).fontSize, px > 0.5 {
            RuleTrace.hit("word-rtl-sakkal-space-is-own-width")
            spans.append(contentsOf: capped(text[start ..< end], run, _indicSpaceStyle(base: style(kind), spaceEm: em, unit: px)))
            start = end
            return
        }
        // (A dot in a right-to-left Sakkal Majalla run: Word draws the face's own period, 0.195 em bold and 0.162 em regular
        // (every Sakkal doc in xb and dx2 agrees), where the stand-in's is 0.232; a "label : ....." line then fits one line; dx2 61a67838.)
        if joinedFace?.joinedSpaceEm != nil, text[start ..< end].allSatisfy({ $0 == "." }), let px = style(kind).fontSize, px > 0.5 {
            RuleTrace.hit("word-rtl-sakkal-dot-is-own-width")
            spans.append(contentsOf: capped(text[start ..< end], run, _indicSpaceStyle(base: style(kind), spaceEm: run.bold ? 0.195 : 0.162, unit: px, glyph: ".")))
            start = end
            return
        }
        // (Spaces between Devanagari words, in a run of its own: Word draws them in Leelawadee UI, 0.274 em, where our stand-in's are 0.22; dx2 fb94294e.)
        if kind >= 0, aumsSpaces, text[start ..< end].allSatisfy({ $0 == " " || ($0 == "\u{00A0}" && spaceBeforeDanda) }) {
            spans.append(contentsOf: capped(text[start ..< end], run, RichLayout._leelaLatinStyle(text[start ..< end], base: joinedScaled(text[start ..< end], style(kind)))))
            start = end
            return
        }
        // (A space in a run of its own whose Latin face is Mangal, in a Devanagari paragraph: Word draws it in Mangal, 0.5 em, 5.52 pt
        // at 11 pt, where the stand-in's Latin space is 3.1; dx2 2db27e2d's "है; उदाहरण", the space after the ";".)
        if kind >= 0, mangalLatinSpace, text[start ..< end].allSatisfy({ $0 == " " || ($0 == "\u{00A0}" && spaceBeforeDanda) }) {
            RuleTrace.hit("word-mangal-latin-run-space-is-half-em")
            let base = style(kind)
            let authored = RichLayout._wordGridSize(run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize, snap: true) * theme.pixelsPerPoint * scale
            spans.append(contentsOf: capped(text[start ..< end], run, _indicSpaceStyle(base: base, spaceEm: 0.5, unit: authored)))
            start = end
            return
        }
        // (A run with no w:cs in an Indic paragraph, Arial Unicode MS in the ascii slot: Word draws its Latin, digits and marks in Yu Gothic; dx2 fb94294e.)
        if kind >= 0, aumsYuInIndic, let y = RichLayout._yuLatinStyle(text[start ..< end], base: joinedScaled(text[start ..< end], style(kind))) {
            spans.append(contentsOf: capped(text[start ..< end], run, y))
            start = end
            return
        }
        if yuOfMissingHangul, text[start ..< end].unicodeScalars.contains(where: { $0.value >= 0x20 && $0.value < 0x250 }) {
            // (Piece by piece: the Latin runs at Yu Gothic's advances, the Hangul between them as it was.)
            var k = start
            while k < end {
                let lat = (text[k].unicodeScalars.first?.value ?? 0x3000) < 0x250
                var m = k
                while m < end, ((text[m].unicodeScalars.first?.value ?? 0x3000) < 0x250) == lat { m = text.index(after: m) }
                let piece = text[k ..< m]
                let st = joinedScaled(piece, style(kind))
                if lat, let y = RichLayout._yuLatinStyle(piece, base: st) {
                    RuleTrace.hit("word-missing-hangul-face-latin-takes-yu-gothic-advances")
                    spans.append(contentsOf: capped(piece, run, y))
                } else { spans.append(contentsOf: capped(piece, run, st)) }
                k = m
            }
            start = end
            return
        }
        // (A stretch with no Indic letter in it, in a run that has some: its digits, marks and spaces are the Latin face's, at the
        // Latin face's widths; the Indic width scale is for the Indic letters. dx2 d912c25b's "(COVID-19)": Word 54.7, ours 59.2.)
        latinNoScale = kind >= 0 && indic != nil && latinFaceNamed && text[start ..< end].contains(where: { $0.isLetter || $0.isNumber }) && !text[start ..< end].unicodeScalars.contains(where: { $0.value == 0xA0 }) && !text[start ..< end].unicodeScalars.contains(where: { $0.value >= 0x0900 && $0.value < 0x0E00 })
        let st = style(kind)
        latinNoScale = false
        if kind >= 0, let cell = latinCell, cell > 0.5, text.distance(from: start, to: end) > 0 {
            let piece = text[start ..< end]
            let styled = joinedScaled(piece, st)
            let t = TextPainter(text: TextSpan(text: String(piece), style: styled), textDirection: .ltr)
            t.layout(minWidth: 0, maxWidth: 100_000)
            let w = t.width
            t.dispose()
            let pad = (w / cell - 0.02).rounded(.up) * cell - w
            if pad > 0.01, w > 0.01 {
                RuleTrace.hit("word-chars-grid-latin-stretch-takes-whole-cells")
                let lastAt = piece.index(before: piece.endIndex)
                spans.append(contentsOf: capped(piece[piece.startIndex ..< lastAt], run, styled))
                spans.append(contentsOf: capped(piece[lastAt ..< piece.endIndex], run, styled.copyWith(letterSpacing: (styled.letterSpacing ?? 0) + pad)))
                start = end
                return
            }
        }
        spans.append(contentsOf: capped(text[start ..< end], run, joinedScaled(text[start ..< end], st)))
        start = end
    }
    func shown(_ c: Character) -> Character {
        guard shownCaps else { return c }
        let up = String(c).uppercased()
        return up.utf16.count == String(c).utf16.count && up.count == 1 ? Character(up) : c
    }
}
