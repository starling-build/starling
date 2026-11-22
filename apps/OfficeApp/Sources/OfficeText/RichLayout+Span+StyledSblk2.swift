// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "StyledSblk2": a step of the styled loop

import Flutter
import FlutterSwiftBridge
import Foundation

extension _StyledFrame {
    @inline(never) func _sblk2() {
    let extra0 = extra
    if ctx.wideSpaces.contains(offset) {
        // (Half an em and the run's own spacing once more,
        // as Word measures it: 8.31pt at 16pt spaced 0.15.
        // A face Word emboldens widens each character by its
        // spread, and the space, a half-width character,
        // by half of it — not by the whole, and not by the
        // Latin stand-in's once more: 5.72pt at 12pt in
        // 楷体_GB2312 bold spaced -0.2, where 6.02 wrapped a
        // line of zh-232090e0 that Word keeps; lab `sp`,
        // 2026-10-14.)
        let s = style(kind)
        let bold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
        let eaFace = theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily
                                         ?? run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, true)
        let own = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
        let spread = bold ? own * theme.pixelsPerPoint * scale : 0
        // (The stand-in's spread is in the style's spacing,
        // which the engine applies and the line above adds
        // once more: off twice.)
        // (An embedded subset is different on Mac with an explicit
        // Latin face: tc22's embedded FangSong_GB2312 over Times or
        // Arial sets plain balanced spaces at 3/8 em, left-aligned
        // or justified. Removing the embedding restores 1/2 em, as
        // do ordinary named FangSong, SimSun, KaiTi and YaHei.
        // Mixed NBSP runs keep their existing half-em rule.)
        // (Whether or not the subset holds a space: lab esp, from
        // zh-d9b085b1, whose FangSong_GB2312 has one — 3/8 em over
        // Times, Arial or Courier New alike, in mode 12 and 15;
        // 1/2 em with the embedding stripped, under 宋体, or under
        // an embedded 黑体, which Word for Mac draws in its own
        // SimHei. Word for Windows: 1/2 em.)
        let missingSpace = !RichTextTheme.wordWindowsPages && ctx.ordinaryBalancedSpaces.contains(offset)
            && latinFace?.isEastAsian == false && eaFace?.drawnFromSubset == true
        // (The subset's spaces keep 3/8 em in bold too,
        // while its ideographs widen: the 12/16/20pt lab.)
        let fraction = missingSpace ? 0.375 : 0.5
        // (Half the run's em as scaled, `w:w`: zh-4e5fe46f's space
        // at w 95 is 4.32 in Word for Windows' print — 10.5 x 0.95
        // / 2 less the doubled spacing — where ours set 4.55.)
        // (A face that carries its own Hangul em, NanumGothic 0.94, spaces at half of it: 4.68 at 10 pt in
        // 397da2bb's Word print, where a Malgun run keeps half an em.)
        var halfBase = em * wScale
        if RichTextTheme.wordWindowsPages, !missingSpace, wScale == 1, spread == 0, let h = eaFace?.otherAdvances?[0xAC00] { halfBase = h * em }
        extra += halfBase * fraction - _spaceWidth(s) + (s.letterSpacing ?? 0)
            - 2 * spread * (latinFace?.boldSpread ?? 0) + (missingSpace ? 0 : spread * (eaFace?.boldSpread ?? 0) / 2)
        // (A trailing space set in the ideographs' face (kind -2)
        // has the stand-in's width in its spacing: that is not
        // the run's own, and not counted twice — zh-9dd9ce6d's
        // five after "…发布" at 14.25pt are 7.15 apiece in Word's
        // print, ours 13.3, and its footer took a line more.)
        // (Not the fit pitch of a w:fitText group, which the space takes
        // once like every character: zh-a4b0f6ea's "单位(盖章)：   年 月 日"
        // set each space 0.07 too wide and 日 2 pt right of Word's.)
        if fitGroup != nil, !fitBusy, let f = fitPitch { extra -= f }
        if kind == -2 {
            let base = style(classed ? RichResolvedFace.characterClass(" ") : 0)
            extra -= 2 * ((s.letterSpacing ?? 0) - (base.letterSpacing ?? 0))
        }
        // (The grid's addition, which the style's spacing holds
        // too, half of it, not twice: zh-f0bd9ea8's two spaces
        // after "第一条" on a grid of -0.21 are 7.9pt apiece at
        // 16pt in Word's print, ours 7.6, and every line took a
        // character Word wraps.)
        if let grid, grid != 0 { extra -= 1.5 * _px(grid) }
    // (A space in a right-to-left run whose complex-script face differs from its Latin one is the complex face's: b514c2's Arial 3.34 pt in Word's print, ours the Latin default's 2.4. Same family in both keeps the Latin table: dx2 Tahoma fa/ur docs.)
    } else if !ea, let face = (narrowLatinInRTL ? nil : (ch == " " && complexSpaceFace != nil && theme.wordRules && RichTextTheme.wordWindowsPages ? complexSpaceFace : latinFace)), (face.advances != nil || (face.boldAdvances != nil && style(kind).fontWeight == .bold)), ch.unicodeScalars.count == 1,
              let u = ch.unicodeScalars.first?.value, u >= 0x20, u <= 0x7E {
        // The width the original face gives this character
        // (`RichResolvedFace.advances`), at the size the
        // style sets it less the stand-in's scales.
        // (A trailing space set in the ideographs' face, kind
        // -2, has the stand-in's width already: measured
        // against the stand-in's own, as any other.)
        let own = kind == -2 ? (classed ? RichResolvedFace.characterClass(" ") : 0) : kind
        let s = style(own)
        let k = Int(u) - 0x20
        if let table = face.advanceTable(bold: s.fontWeight == .bold, italic: s.fontStyle == .italic), k < table.count, table[k] > 0, let px = s.fontSize, px > 0.5 {
            let classScale = classed ? face.classScales.flatMap { own >= 0 && own < $0.count ? $0[own] : nil } ?? 1 : 1
            var target = table[k] * px / (face.sizeScale * classScale)
            // (Kerned with the next of the run by the original's
            // pair, where the run kerns at its size: zh-d89c3840's
            // "（TC）" in YaHei at 16pt, "T" 8.4 in Word's print
            // where its advance is 9.17, and its line took "秘".)
            let kernsFrom: Double? = run.kerningFrom ?? named?.char.kerningFrom ?? _normalChar(document)?.kerningFrom
            let points: Double = run.fontSize ?? named?.char.fontSize ?? theme.fontSize
            let pairs: [UInt32: Double]? = s.fontWeight == .bold ? face.boldKerns : face.kerns
            if theme.wordRules || face.kernsOutsideWord, let from = kernsFrom, from > 0, points >= from, let pairs, after < text.endIndex,
               let v0 = shown(text[after]).unicodeScalars.first?.value, case let v = v0 == 0xA0 ? 0x20 : v0, v >= 0x20, v <= 0x7E, let pair = pairs[(u == 0xA0 ? 0x20 : u) << 8 | v] {
                target += pair * px / (face.sizeScale * classScale)
            }
            // (On the print's grid too, kerned as the stand-in
            // kerns, where the theme has one: `advanceGrid`.)
            if let grid = theme.advanceGrid, grid > 0 {
                let size = run.fontSize ?? named?.char.fontSize ?? theme.fontSize
                let kerns = (run.kerningFrom ?? named?.char.kerningFrom).map { $0 > 0 && size >= $0 } ?? false
                if kerns, let following { target += _pairAdvance(s, ch, following) - _glyphWidth(s, ch) }
                // (A face PowerPoint has measured widths for sets its glyphs on a thousandth of an em, as its print shows: Aptos digits
                // 9.612 at 18 pt, not the eighth of a point's 9.625; the stand-in faces keep the eighth.)
                let g = theme.advanceGridOfFaceTables ? 0.001 * px : grid * theme.pixelsPerPoint * scale
                if g > 0 { target = (target / g).rounded() * g }
            }
            extra += target - _glyphWidth(s, ch)
        }
    } else if !ea, !ch.isNewline, let face = latinFace, face.kernsReplaceShaped, style(kind).fontStyle != .italic, ch.unicodeScalars.count == 1,
              let u = ch.unicodeScalars.first?.value, u > 0x20, u <= 0xFF, u != 0xA0, let px = style(kind).fontSize, px > 0.5,
              let from = run.kerningFrom ?? named?.char.kerningFrom ?? _normalChar(document)?.kerningFrom, from > 0,
              (run.fontSize ?? named?.char.fontSize ?? theme.fontSize) >= from, after < text.endIndex,
              let nx = shown(text[after]).unicodeScalars.first?.value, nx > 0x20, nx <= 0xFF, nx != 0xA0 {
        // (Calibri's own kern pairs in place of the stand-in's: PowerPoint's print kerns re, ra, te, st... by the font's table, pair by pair.)
        let s = style(kind)
        let pairs: [UInt32: Double]? = s.fontWeight == .bold ? face.boldKerns : face.kerns
        extra += (pairs?[u << 8 | nx] ?? 0) * px - _pairKern(s, ch, shown(text[after]))
    } else if !ea, theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, u == 0x2266 || u == 0x2267,
              ch.unicodeScalars.count == 1, let w = RichLayout._cambriaMathOpeners2[u],
              text[..<i].last.map({ $0.isASCII && ($0.isLetter || $0.isNumber) }) == true {
        // (Cambria has no "≦" or "≧": Word for Windows sets them in Cambria Math, 0.7471 em wide;
        // after a Latin letter or digit; after an ideograph it stays the East Asian face's full width (lab c2301a p3 "で≦2fm"). The fallback face's 0.84 pushed jpn-z21601833-c2301a's "…CHSH≦2、完" a character over.)
        extra += w * em - _glyphWidth(style(kind), ch)
    } else if !ea, let grid = theme.advanceGrid, grid > 0, latinFace?.advances == nil, ch != "\t", !ch.isNewline, !(!theme.wordRules && joinedFace != nil && isArabic(ch)),
              latinFace?.otherAdvances.flatMap({ t in ch.unicodeScalars.first.flatMap { t[$0.value] } }) == nil,
              ch.unicodeScalars.first.map({ $0.value >= 0x20 && $0.value < 0x2E80 }) ?? false {
        // On the print's grid (`advanceGrid`) — kerned with the
        // next where the run kerns at its size (`kerningFrom`).
        let s = style(kind)
        let size = run.fontSize ?? named?.char.fontSize ?? theme.fontSize
        let kerns = (run.kerningFrom ?? named?.char.kerningFrom).map { $0 > 0 && size >= $0 } ?? false
        let w = kerns && following != nil ? _pairAdvance(s, ch, following!) : _glyphWidth(s, ch)
        let g = grid * theme.pixelsPerPoint * scale
        if g > 0, w > 0 { extra += (w / g).rounded() * g - w }
    } else if !ea, theme.wordRules, RichTextTheme.wordWindowsPages, ch.unicodeScalars.count == 1, let u = ch.unicodeScalars.first?.value, u >= 0x180,
              let own = latinFace, own.completeCoverage, own.otherAdvances?[u] == nil,
              let fbName = RichResolvedFace._scriptFallbackFace(u, sans: own.sansClass),
              let fw = ScriptFallbackWidths.table(fbName, bold: style(kind).fontWeight == .bold)?[u] {
        // (A character the face lacks is drawn, and measured, in the face Word falls back to for its script.)
        RuleTrace.hit("missing-character-takes-script-fallback-face-width")
        extra += fw * em - _glyphWidth(style(kind), ch)
    } else if !ea, !nbspHAnsi, let u = ch.unicodeScalars.first?.value,
              // (A Hangul syllable in Slides already took its Malgun em from the rule in the main loop: not added again, which stepped 1.08 em, lab fit1.)
              !(!theme.wordRules && u >= 0xAC00 && u <= 0xD7A3),
              let face = (u >= 0x80 && highFace?.otherAdvances?[u] != nil ? highFace : nil) ?? latinFace, face.otherAdvances != nil,
              // (A letter with its marks, where the table has each:
              // Thai's "ต่", "คำ" — `OfficeFonts.browalliaAdvances`.)
              ch.unicodeScalars.count == 1 || (u >= 0x0E00 && u < 0x0E80 && ch.unicodeScalars.allSatisfy { face.otherAdvances?[$0.value] != nil })
                  || (ch.unicodeScalars.count == 2 && ch.unicodeScalars.last?.value == 0xFE0E && face.otherAdvances?[0xFE0E] != nil),
              // (Not a no-break space after an ordinary one, through
              // others: that is the Latin text's, the space's half
              // em — zh-f3802561's "第一条" + U+00A0, U+0020, U+00A0,
              // U+00A0 in a 10.5pt 仿宋 run sets them 10.5, 5.25,
              // 5.25 and 5.25 in Word's print; ours set every
              // no-break one an em, and the line lost its "发".)
              // (Nor one after a Latin letter or digit: zh-a7a889eb's
              // 12pt 宋体 "3.5" + U+00A0 + U+0020 sets them 6 and 6,
              // and its line took "业 贰 级" ours left for the next.
              // After a "." it is an em still — zh-17749c13's
              // "1." + U+00A0 + "船" is 14 at 14pt.)
              !(theme.wordRules && u == 0xA0 && text[..<i].reversed().first(where: { $0 != "\u{00A0}" }).map({ $0 == " " || ($0.isASCII && ($0.isLetter || $0.isNumber)) }) == true) {
        // … and the width it gives one the stand-in lacks.
        // (Past ASCII, the `w:hAnsi` face's, where it has its own:
        // zh-17749c13's no-break spaces in 仿宋_GB2312 runs whose
        // hAnsi is 宋体 are SimSun's, an em each in Word's print.)
        let s = style(kind)
        let own = face.family == latinFace?.family
        let table = face.otherTable(bold: s.fontWeight == .bold, italic: s.fontStyle == .italic)
        let each = ch.unicodeScalars.map { table?[$0.value] }
        if !each.contains(where: { $0 == nil }), let w = Optional(each.reduce(0) { $0 + ($1 ?? 0) }), let px = s.fontSize, px > 0.5 {
            let classScale = classed ? face.classScales.flatMap { kind >= 0 && kind < $0.count ? $0[kind] : nil } ?? 1 : 1
            var target = own ? w * px / (face.sizeScale * classScale) : w * em
            // (On the print's grid, where the theme has one.)
            if let grid = theme.advanceGrid, grid > 0 {
                let g = grid * theme.pixelsPerPoint * scale
                if g > 0 { target = (target / g).rounded() * g }
            }
            extra += target - _glyphWidth(s, ch)
        }
    }
    // (PowerPoint sets the font at a size on a grid of 1/600 in: 32 pt prints at 32.04, so every advance is that much wider; the line's
    // height is the unrounded size's. `fontSizeGrid`.)
    if theme.fontSizeGrid > 0, !ch.isNewline, !ea, latinFace?.kernsReplaceShaped == true {
        var pt = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
        if fontScale != 1 { pt = max(1, (pt * fontScale).rounded()) }
        let q = (pt / theme.fontSizeGrid).rounded() * theme.fontSizeGrid
        if pt > 0, q > 0, q != pt { extra += (_glyphWidth(style(kind), ch) + extra - extra0) * (q / pt - 1) }
    }
    }
}
