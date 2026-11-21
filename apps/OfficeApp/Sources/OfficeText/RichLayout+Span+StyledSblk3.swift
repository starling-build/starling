// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "StyledSblk3": a step of the styled loop

import Flutter
import FlutterSwiftBridge
import Foundation

extension _StyledFrame {
    @inline(never) func _sblk3() {
    @inline(never) func _r2() {
    if let following {
        // (Not beside a note's number: zh-499adba6's — "（SDGs）⁷作
        // 為", "權能⁸，" (mode 14, 12pt) — have none either side in
        // Word's print, and its line "…增強所有婦女和女" takes the
        // last "女" there, 3pt nearer than ours. Other raised or
        // lowered text keeps them: zh-27083953's "PM₂.₅为", "O₃为".)
        let nextAt = offset + ch.utf16.count
        let besideRaised = theme.wordRules && ((offset < raised.count && raised[offset]) || (nextAt < raised.count && raised[nextAt]))
        // (That holds for DIGITS only: a run of Latin LETTERS with eastAsia "Times New Roman" keeps its space beside
        // Hangul or kana in Word's print: dx2 ko 43e0fe21 "저희는ACECQA와", xd 03cd29dc "K 리그", xb jpn-z17350624 "AI と".)
        // (Not where the Latin character's run names a Latin face for East Asian text, in Word for
        // Windows: zh-cd48112c's digit runs say eastAsia "Times New Roman", and its print has no space
        // either side of 138 digits; zh-a0e932c2's say 宋体, and it has its 5.3 at 39.)
        // (Nor anywhere in a document whose defaults name a Latin face for East Asian text: lab `asd`
        // (Word for Windows, mode 15, 15pt): docDefaults eastAsia Times New Roman sets "…30…" between
        // 宋体 ideographs with no space at all, whatever the digit run says — none, Times, Times with
        // hint eastAsia, all Times, 宋体 with the hint; with 宋体 there, a quarter em in all five.
        // zh-a0e932c2's gaps of 5.3 are its typed spaces.)
        if theme.wordRules, document.usesEastAsianLayout || (document.autoSpacesWithoutFELayout && document.eastAsianLineRules && (document.defaultLangXML?.containsSubstring("w:eastAsia=\"") == true || ((document.compatibilityMode ?? 15) < 15)) && RichTextTheme.wordWindowsPages), !besideRaised, !(RichTextTheme.wordWindowsPages && document.skipsAutoSpace), RichLayout._autoSpaced(ch, following, p.style, compat: document.compatibilityMode ?? 12),
           !(RichTextTheme.wordWindowsPages && document.eastAsianDefaultFaceIsLatin),
           !(RichTextTheme.wordWindowsPages && ((ch.unicodeScalars.first?.value ?? 0) >= 0x2E80 ? following : ch).isNumber && eastAsianFaceIsLatin(atOffset: eaFaceOffset(ch, following, offset, nextAt))) {
            let latin = run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily
            // (Of the grid's character, where there is a grid
            // of them, and of the run's spacing with it; a
            // flat quarter of the two where the widths are
            // balanced — measured 4.0pt at 16pt, and 3.6 in
            // Times without.)
            // (… and of the grid's: 4.25pt either side of a
            // digit at 16pt on that grid of 1.008.)
            var gap = document.balancesSpaceWidth
                // (A shrunk grid does not shrink it in a cell: lab `dig` (Word for Windows, zh-9c162f26's 9pt
                // mode-14 cell, grid -0.21) cuts "应" between 4.21 and 4.31 over on a line with three digit
                // boundaries and between 4.31 and 4.41 with none, the 0.15pt a quarter of the full em (2.25) over
                // a quarter of the shrunk one (2.20) makes three times. In the body it does shrink it: zh-d68ac84a
                // (grid -1.35), zh-eb54d3b0 and zh-8d6f702e lose lines with the full em.)
                ? (em + _px(p.cell != nil ? max(0, grid ?? 0) : (grid ?? 0)) + 2 * spacing) / 4
                : RichTextTheme.wordWindowsPages && ch.isASCII == false && (following.isNumber || following.isLetter) && following.isASCII
                // (Letters the same as digits: lab jsp2, 9 prints, 7 faces, 14 and 10.5 pt: ideograph then letter a quarter em in
                // every face, letter then ideograph half the face's OS/2 xAvgCharWidth.)
                // (Each side its own, in Word for Windows: lab asz (zh-147bdae0's package, left-aligned,
                // sizes varied) sets an ideograph then a digit a quarter of the ideograph's em apart —
                // 3.00 at 12pt, 3.96-4.08 at 16, 2.28 at 9, whatever the digit's size — and a digit then
                // an ideograph half the digit face's average width apart — Times 2.40 at 12pt, 1.86 at 9,
                // 3.30 at 16, 標楷體 3.00 — whatever the ideograph's. Ours set both 2.70 beside Times, and
                // lab asp's line took its character a step late.)
                ? (em + _px(grid ?? 0) + spacing) / 4
                : RichTextTheme.wordWindowsPages && (ch.isNumber || ch.isLetter) && ch.isASCII && following.isASCII == false
                ? (2 * (theme.averageCharWidth?(latin) ?? 0.5) * (em + _px(grid ?? 0)) + spacing) / 4 * wScale
                : ((0.5 + (theme.averageCharWidth?(latin) ?? 0.5)) * (em + _px(grid ?? 0)) + spacing) / 4
            // (Twice inside text ruled round where the widths are
            // balanced: labs `ap1`–`ap4`, zh-06c46ba9's boxed
            // "範例1" sets "例" and "1" 21.1pt apart at 14pt in
            // Word's print, 17.5 without the border or without
            // the balance. Its reference lists took a character
            // a line that Word wraps.)
            // (A border said to be none is none: zh-f10c8f34's body runs
            // carry `<w:bdr w:val="none"/>`, and Word sets "14号" with
            // 2pt between, a quarter of its 8pt; ours took the run for
            // ruled and set 4, and every line held a character less.)
            if document.balancesSpaceWidth, let xml = run.keptXML, let r = xml.rangeOfSubstring("<w:bdr "),
               case let tag = xml[r.upperBound...].prefix(while: { $0 != ">" }),
               !tag.containsSubstring("w:val=\"none\""), !tag.containsSubstring("w:val=\"nil\"") { gap *= 2 }
            extra += gap
            autoSpaces?(offset, gap)
        } else if ea, closes, RichLayout.closesUp(ch, following, centred: document.marksCentred)
                    // (A middle dot after a closing mark closes it up too, in kana text at compat 15 on a grid: lab
                    // `jis4051`, Word for Windows, sets "」・" with the 」 at its half like "」。".)
                    || (following == "\u{30FB}" && RichLayout._closingBracketMarks.contains(ch) && RichTextTheme.wordWindowsPages && theme.wordRules
                        && (document.compatibilityMode ?? 12) >= 15 && document.lineGridPitch != nil
                        && (document.hasKana || document.eastAsiaLanguage?.hasPrefix("ja") == true))
                    // (And a middle dot before an OPENING mark sits at its half, in a Japanese document on a line grid:
                    // xb jpn-z23002680-771abc's "・『フランク" sets ・ 5.3 pt at 10.56 (『 at +0.5 em), so its line holds
                    // "年代" where ours broke after "年"; xd a91d8fed (compat 14), f42177d2 and jpn 1e9281 agree; a
                    // Pandoc file with no grid (4e6465) keeps the whole em.)
                    || (ch == "\u{30FB}" && RichLayout._openingMarks.contains(following) && RichTextTheme.wordWindowsPages && theme.wordRules
                        && document.lineGridPitch != nil && (document.hasKana || document.eastAsiaLanguage?.hasPrefix("ja") == true))
                    // (The quote's own run says whether it is full-width, where the mark
                    // ends its run: zh-3ab8a2fb's "，" unhinted before a "“" hinted East
                    // Asian closes up, 7.13 in Word's print, and its line takes "机".)
                    || (fullQuotes && !narrowQuotes && (following == "\u{201C}" || following == "\u{2018}") && RichLayout._closingMarks.contains(ch)
                        && RichLayout.isEastAsian(following, hinted: after < text.endIndex ? hinted : runHinted(atOffset: base + text.utf16.count)))
                    // (And before a full-width closing quote, mid-line with room as well: lab `sqp`
                    // (Word for Windows, zh-424775e4's p5 line, SimSun 12, kerned) sets "。”" 6 + 12 in
                    // modes 12 and 15 and under doNotCompress alike, and takes "机，" 6pt sooner than ours
                    // did with the "。" a whole em; the "。" not centred, as a closing bracket's.)
                    || (fullQuotes && !narrowQuotes && (following == "\u{201D}" || following == "\u{2019}") && RichLayout._closingMarks.contains(ch)
                        && !(document.marksCentred && "，。、；：！？".contains(ch))
                        && RichLayout.isEastAsian(following, hinted: after < text.endIndex ? hinted : runHinted(atOffset: base + text.utf16.count)))
                    // (Not a face's own narrow quote, which has no
                    // blank to give: zh-0aac9d1a's Arial Unicode MS
                    // "黑名单”。" keeps its 5.52pt "”" before the "。" in
                    // Word's print; ours took half an em off it, all of
                    // it, and the line took a "省" Word wraps.)
                    || (fullQuotes && !narrowQuotes && (ch == "\u{201D}" || ch == "\u{2019}") && RichLayout.isEastAsian(ch, hinted: hinted)
                        && (RichLayout._closingMarks.contains(following) || RichLayout._openingMarks.contains(following)
                            || ((following == "\u{201C}" || following == "\u{2018}") && RichLayout.isEastAsian(following, hinted: hinted)))) {
            // (A closing mark before a full-width opening quote
            // gives its half as before any opening mark: zh-15728c84's
            // "微信、“12345”" sets "、" 5pt wide at 10pt in Word's print.)
            // (And a full-width closing quote is a closing mark
            // itself: the same document's "线上线下”、“舆情" sets
            // "”" and "、" 5.2 and 5.3pt wide at 10.5, and a cell
            // line took the character after "主体；" that ours
            // left for the next. Where punctuation does not kern
            // — `w:noPunctuationKerning`, zh-d68ac84a's "”（" —
            // the quote keeps its em, as the marks do.)
            // (Half its cell, on a character grid: labs `og3`/`og4`
            // (Word for Windows, zh-eb54d3b0's package, 16pt)
            // set "》，" "）、" "，“" 7.9 apart on a grid of -0.21
            // and 8.5 on one of +1 — half the em and half the
            // addition. Ours kept the whole addition, and
            // zh-eb54d3b0's "…政策》，助推茶" took "产" 7.81 over
            // where Word's is 7.91 and goes down.)
            // (A spaced closing quote gives half its spaced width:
            // lab `p01`, zh-01bbcd4d's "…组织成员”。" at 16pt spaced
            // to 17 sets the "”" 8.49 before the "。" in Word's
            // print; ours, half the em off, 9.0.)
            // (And a mark condensed keeps half its condensed width:
            // zh-5be7e156's Normal, spaced -0.3 with the widths
            // balanced (so -0.6 a full-width character) on a grid
            // of -0.21, sets "）、" and "》（" 7.6 apart in Word's
            // print — half of 15.2 — where ours, half the em off
            // and all of the spacing kept, set 7.3, and its p1
            // line took a "家" Word leaves.)
            // (Any closing mark the same: zh-01bbcd4d's "…不提交竣工材料）；" sets the "）" 8.52 before the "；"
            // in Word's print, half of its 17; ours, 9.0, left "料）；" 0.2pt short of the line Word takes.)
            let quoteAdd = theme.wordRules ? max(0, spacing) * (doubles ? 2 : 1) : 0
            let condensed = theme.wordRules && spacing < 0 ? spacing * (doubles ? 2 : 1) : 0
            extra -= (em + _px((kind < 0 ? ideographGrid : grid) ?? 0) + quoteAdd + condensed) / 2
        }
    }
    }
    _r2()
    }
}
