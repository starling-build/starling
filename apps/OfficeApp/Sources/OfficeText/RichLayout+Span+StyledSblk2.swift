// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "StyledSblk2": a step of the styled loop

import Flutter
import FlutterSwiftBridge
import Foundation

extension _StyledFrame {
    @inline(never) func _sblk2() {
    let extra0 = extra
    var done576 = false
    var kernTrue = 0.0, kernEngine = 0.0   // (the pair kern in px: the face's own, and the stand-in's that the engine adds)
    if ctx.averageSpaces.contains(offset), let average = theme.averageCharWidth {
        // (The Latin face's OS/2 average width, scaled by `w:w`; see `averageSpaces`.)
        let latin = run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily
        extra += average(latin) * em * wScale - _spaceWidth(style(kind))
    }
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
    } else if !ea, theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, run.rightToLeft, ch == "(" || ch == ")",
              (run.fontHint ?? named?.char.fontHint ?? _normalChar(document)?.fontHint) == "cs", let face = joinedFace, face.joinedAdvances != nil, style(kind).fontWeight == .bold,
              let em = face.joinedBracketEm,
              let px = style(kind).fontSize, px > 0.5 {
        // (An ASCII bracket in a right-to-left run marked w:hint="cs" is the complex-script face's own, not the Latin face's: Traditional
        // Arabic's are 0.278 em in Word's prints, where the Latin stand-in's 0.41 carried ara-z11030406 p3's first line one word short. Bold only: 628 bold brackets measured at it; the regular ones in xb ara-z4399437 stand as they were.)
        RuleTrace.hit("word-hint-cs-ascii-bracket-takes-the-complex-face-width")
        extra += em * px - _glyphWidth(style(kind), ch)
    } else if ch == " ", let em = joinedFace?.joinedSpaceEm, !theme.wordRules, let px = style(kind).fontSize, px > 0.5 {
        // (A space of a right-to-left run set in a face with its own space, Simplified Arabic 0.3174 em, Sakkal Majalla 0.1514: the face's
        // width, where the stand-in's Latin space is 0.22 em.)
        RuleTrace.hit("word-rtl-joined-face-space-is-own-width")
        extra += em * px - _glyphWidth(style(kind), " ")
    } else if !ea, let face = (narrowLatinInRTL ? nil : (ch == " " && complexSpaceFace != nil && theme.wordRules && RichTextTheme.wordWindowsPages ? complexSpaceFace : latinFace)), (face.advances != nil || (face.boldAdvances != nil && style(kind).fontWeight == .bold) || (face.italicAdvances != nil && style(kind).fontStyle == .italic)), ch.unicodeScalars.count == 1,
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
            // (Snapped to the face's font units: the tables carry four decimals, which turn an exact half-step of the eighth-point grid
            // into the wrong side, 64f938d1 p4's 401.875 against a 401.725 box.)
            var unitsV = table[k]
            for upm in [256.0, 2048.0, 1000.0, 1024.0] {
                let n = (unitsV * upm).rounded()
                if abs(unitsV - n / upm) <= 0.00006 { unitsV = n / upm; break }
            }
            var target = unitsV * px / (face.sizeScale * classScale)
            let glyphOnGrid = false   // (a Latin face with a table keeps its rounding below: Century Schoolbook and Malgun at the eighth, 66517aeb and ko-87d15438 5 to 5.2 worse)
            // (Kerned with the next of the run by the original's
            // pair, where the run kerns at its size: zh-d89c3840's
            // "（TC）" in YaHei at 16pt, "T" 8.4 in Word's print
            // where its advance is 9.17, and its line took "秘".)
            let kernsFrom: Double? = run.kerningFrom ?? named?.char.kerningFrom ?? _normalChar(document)?.kerningFrom
            let points: Double = run.fontSize ?? named?.char.fontSize ?? theme.fontSize
            var kernUnits: Double? = nil
            let pairs: [UInt32: Double]? = face.kernPairs(bold: s.fontWeight == .bold, italic: s.fontStyle == .italic)
            if theme.wordRules || face.kernsOutsideWord || (face.kernsReplaceShaped && face.advances == nil), let from = kernsFrom, from > 0, points >= from, let pairs, after < text.endIndex,
               let v0 = shown(text[after]).unicodeScalars.first?.value, case let v = v0 == 0xA0 ? 0x20 : v0, v >= 0x20, v <= 0x7E, let pair = pairs[(u == 0xA0 ? 0x20 : u) << 8 | v] {
                target += pair * px / (face.sizeScale * classScale)
                kernUnits = pair
            }
            // (On the print's grid too, kerned as the stand-in
            // kerns, where the theme has one: `advanceGrid`.)
            if let grid = rl.activeAdvanceGrid, grid > 0 {
                let size = run.fontSize ?? named?.char.fontSize ?? theme.fontSize
                let kerns = (run.kerningFrom ?? named?.char.kerningFrom).map { $0 > 0 && size >= $0 } ?? false
                if kerns, !(face.kernsReplaceShaped && face.advances == nil), let following { target += _pairAdvance(s, ch, following) - _glyphWidth(s, ch) }
                // (A face PowerPoint has measured widths for sets its glyphs on a thousandth of an em, as its print shows: Aptos digits
                // 9.612 at 18 pt, not the eighth of a point's 9.625; the stand-in faces keep the eighth.)
                let g = theme.advanceGridOfFaceTables ? 0.001 * px : grid * theme.pixelsPerPoint * scale
                if theme.fontSizeGrid > 0, !ea, u < 0x0590 {
                    // (576 dpi: the bare advance and the pair kern each round to an eighth of a point at ppem = round(size x 8).)
                    var pt = points
                    if fontScale != 1 { pt = max(1, (pt * fontScale).rounded()) }
                    let ppem = (pt * 8).rounded()
                    if pt > 0, ppem >= 8 {
                        let k = px / (face.sizeScale * classScale) / pt
                        var t = (unitsV * ppem).rounded() / 8 * k
                        if let kk = kernUnits { t += (kk * ppem).rounded() / 8 * k }
                        target = t; done576 = true
                    }
                } else if g > 0, !glyphOnGrid { target = (target / g).rounded() * g }
            }
            let natural = _glyphWidth(s, ch)
            var break_scaled = false
            if face.kernsReplaceShaped, face.advances == nil, kind >= 0, !(s.letterSpacing != nil && s.letterSpacing != 0) {
                // (A face whose own kern pairs replace the stand-in's: the glyph's advance in the text is the stand-in's pair advance, kern
                // and all, not `natural`, which is measured between two x's and carries their kerning. Calibri Italic, same metrics as Carlito
                // Italic bar a few font units: the width the print gives is the table's, kerned by its own pairs.)
                let inText = after < text.endIndex ? _pairAdvance(s, ch, shown(text[after])) : natural
                extra += target - inText
                break_scaled = true
            }
            if !break_scaled, theme.scalesGlyphsToTables, natural > 0.5, kind >= 0, !(s.letterSpacing != nil && s.letterSpacing != 0) {
                // (The glyph's own advance by a scale, the kerning and the grid by the spacing.)
                let own = unitsV * px / (face.sizeScale * classScale)
                let r = own / natural
                if r > 0.5, r < 2, abs(r - 1) > 0.005 { glyphScale = r; extra += target - own; break_scaled = true }
            }
            if !break_scaled { extra += target - natural }
        }
    } else if !ea, !ch.isNewline, let face = latinFace, face.kernsReplaceShaped, style(kind).fontStyle != .italic || face.italicKerns != nil, ch.unicodeScalars.count == 1,
              let u = ch.unicodeScalars.first?.value, u > 0x20, u <= 0xFF || (u >= 0x2010 && u <= 0x2027), u != 0xA0, let px = style(kind).fontSize, px > 0.5,
              let from = run.kerningFrom ?? named?.char.kerningFrom ?? _normalChar(document)?.kerningFrom, from > 0,
              (run.fontSize ?? named?.char.fontSize ?? theme.fontSize) >= from, after < text.endIndex,
              let nx = shown(text[after]).unicodeScalars.first?.value, nx > 0x20, nx <= 0xFF || (nx >= 0x2010 && nx <= 0x2027), nx != 0xA0 {
        // (Calibri's own kern pairs in place of the stand-in's: PowerPoint's print kerns re, ra, te, st... by the font's table, pair by pair.)
        let s = style(kind)
        let pairs: [UInt32: Double]? = face.kernPairs(bold: s.fontWeight == .bold, italic: s.fontStyle == .italic)
        kernEngine = _pairKern(s, ch, shown(text[after]))
        kernTrue = (pairs?[u > 0xFF || nx > 0xFF ? u << 16 | nx : u << 8 | nx] ?? 0) * px
        extra += kernTrue - kernEngine
    } else if !ea, theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, u == 0x2266 || u == 0x2267,
              ch.unicodeScalars.count == 1, let w = RichLayout._cambriaMathOpeners2[u],
              text[..<i].last.map({ $0.isASCII && ($0.isLetter || $0.isNumber) }) == true {
        // (Cambria has no "≦" or "≧": Word for Windows sets them in Cambria Math, 0.7471 em wide;
        // after a Latin letter or digit; after an ideograph it stays the East Asian face's full width (lab c2301a p3 "で≦2fm"). The fallback face's 0.84 pushed jpn-z21601833-c2301a's "…CHSH≦2、完" a character over.)
        extra += w * em - _glyphWidth(style(kind), ch)
    } else if !ea, let grid = rl.activeAdvanceGrid, grid > 0, latinFace?.advances == nil, ch != "\t", !ch.isNewline, !(!theme.wordRules && joinedFace != nil && isArabic(ch)),
              latinFace?.otherAdvances.flatMap({ t in ch.unicodeScalars.first.flatMap { t[$0.value] } }) == nil,
              ch.unicodeScalars.first.map({ $0.value >= 0x20 && $0.value < 0x2E80 }) ?? false {
        // On the print's grid (`advanceGrid`) — kerned with the
        // next where the run kerns at its size (`kerningFrom`).
        let s = style(kind)
        let size = run.fontSize ?? named?.char.fontSize ?? theme.fontSize
        let kerns = (run.kerningFrom ?? named?.char.kerningFrom).map { $0 > 0 && size >= $0 } ?? false
        let w = kerns && following != nil ? _pairAdvance(s, ch, following!) : _glyphWidth(s, ch)
        let g = grid * theme.pixelsPerPoint * scale
        if g > 0, w > 0 { extra += (w / g + 0.5 + 1e-7).rounded(.down) * g - w }
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
            var return_scaled = false
            let classScale = classed ? face.classScales.flatMap { kind >= 0 && kind < $0.count ? $0[kind] : nil } ?? 1 : 1
            var target = own ? w * px / (face.sizeScale * classScale) : w * em
            // (On the print's grid, where the theme has one.)
            if let grid = rl.activeAdvanceGrid, grid > 0 {
                let g = grid * theme.pixelsPerPoint * scale
                if g > 0 { target = (target / g + 0.5 + 1e-7).rounded(.down) * g }
            }
            let natural = _glyphWidth(s, ch)
            // (A kana or CJK mark of a proportional face with a table: the stand-in's one-em glyph drawn at the face's narrower advance by a
            // horizontal scale, as the Latin glyphs are above (brackets keep their own placement: their ink sits to one side of the slot), not crowded into the next slot.)
            if theme.scalesGlyphsToTables, own, ch.unicodeScalars.count == 1, u >= 0x3000, u < 0xFFF0, ch.unicodeScalars.first?.properties.generalCategory != .openPunctuation, ch.unicodeScalars.first?.properties.generalCategory != .closePunctuation, ch.unicodeScalars.first?.properties.generalCategory != .otherPunctuation, natural > 0.5, !(s.letterSpacing != nil && s.letterSpacing != 0), target > 0 {
                let r = (w * px / (face.sizeScale * classScale)) / natural
                if r > 0.5, r < 0.98 { RuleTrace.hit("cjk-glyph-scaled-to-proportional-advance"); glyphScale = r; glyphSqueeze = natural - w * px / (face.sizeScale * classScale); extra += target - natural; return_scaled = true }
            }
            if !return_scaled { extra += target - natural }
        }
    }
    // (PowerPoint lays the text out on a 576 dpi device: the font is at ppem = round(size x 8) and every glyph advances round(em x ppem) eighths of a point, for every face and size
    // (planner spec v3, 2026-11-22). 32 pt prints at 32.04, 16 pt at 15.96. The line's height is the unrounded size's.)
    if theme.fontSizeGrid > 0, !done576, !ch.isNewline, !ea, ch.unicodeScalars.count == 1, ch.unicodeScalars.first!.value < 0x0590, latinFace?.kerns != nil, let st = Optional(style(kind)), let fpx = st.fontSize, fpx > 0.5 {
        var pt = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
        if fontScale != 1 { pt = max(1, (pt * fontScale).rounded()) }
        let ppem = Int((pt * 8).rounded())
        if pt > 0, ppem >= 8 {
            // (The bare advance and the pair kern round separately, each to an eighth of a point.)
            let bare = (abs(extra - extra0 - (kernTrue - kernEngine)) < 1e-9 ? _bareAdvance(st, ch) : _glyphWidth(st, ch)) + (extra - extra0) - (kernTrue - kernEngine)
            func r8(_ v: Double) -> Double { let ss = max(0.1, latinFace?.sizeScale ?? 1); return Double((v / fpx * ss * Double(ppem)).rounded()) / 8 * (fpx / (pt * ss)) }
            if bare > 0 { extra += r8(bare) - bare + (kernTrue != 0 ? r8(kernTrue) - kernTrue : 0) }
        }
    }
    }
}
