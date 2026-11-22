// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "StyledSblk4": a step of the styled loop

import Flutter
import FlutterSwiftBridge
import Foundation

extension _StyledFrame {
    @inline(never) func _sblk4() {
    if heldSpaces.contains(offset) {
        flush(i)
        if koreanSpaces.contains(offset) {
            spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
            ctx.inserts.append(offset)
        }
        // (A held space of a run that names its own Latin face is that face's, not stretched by the Indic scale: the probe sets it so.)
        latinNoScale = kind >= 0 && indic != nil && run.fontFamily != nil
        let s = style(kind)
        latinNoScale = false
        if theme.wordRules, RichTextTheme.wordWindowsPages, !document.underlinesTrailingSpaces, windowsCounted.contains(offset) {
            // (Counted under Word for Windows' rule for a paragraph's
            // closing spaces that open underlined
            // (`_underlinedClosingCounted`): held to the word before
            // them, the run as wide as it reaches past half the
            // line, and not underlined.)
            let width = _glyphWidth(s, " ") + extra
            if ctx.windowsShare == nil {
                let whole = width * Double(windowsCounted.count)
                // (No more than lets the word before them stand on a
                // line of its own whole: Word sets it there however
                // far the spaces reach, where the engine would part
                // a word wider than the line.)
                let units = Array(p.text.utf16)
                var word = 0.0, k = offset - 1
                while k >= 0, units[k] != 0x20, units[k] < 0x2E80, let u = Unicode.Scalar(units[k]) {
                    word += _glyphWidth(s, Character(u))
                    k -= 1
                }
                let reach = min(whole - textWidth / 2, textWidth - word - _px(0.5))
                ctx.windowsShare = whole > 0 ? max(0, reach) / whole : 0
            }
            var plain = s.copyWith(decoration: TextDecoration.none)
            plain = plain.copyWith(letterSpacing: (s.letterSpacing ?? 0) + width * (ctx.windowsShare ?? 0) - _glyphWidth(s, "\u{2007}"))
            spans.append(TextSpan(text: "\u{2007}", style: plain))
        } else if theme.wordRules, document.underlinesTrailingSpaces, run.underline {
            // (An underlined one under `w:ulTrailSpace` as a figure
            // space of the space's width: the engine hangs a run of
            // no-break spaces past the margin as it does plain ones,
            // where Word wraps it.)
            spans.append(TextSpan(text: "\u{2007}", style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra + _glyphWidth(s, " ") - _glyphWidth(s, "\u{2007}"))))
        } else if theme.wordRules, RichTextTheme.wordWindowsPages, RichLayout._afterBreakRun(Array(p.text.utf16), offset) {
            // (A space run that opens a line after a manual break: a figure space of the space's width, which the engine keeps at a line start where a no-break space collapses.)
            spans.append(TextSpan(text: "\u{00A0}", style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra + _glyphWidth(s, " ") - _glyphWidth(s, "\u{00A0}"))))
        } else {
            var heldStyle = extra != 0 ? s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra) : s
            // (A tab held as a no-break space sets no line beside text, as a run of tabs sets none: sa1 7770c637's
            // justified contents line "I.<tab>RESUMEN…", its tab in Calibri 11 among 9pt Courier New raised 2pt, is
            // 24.36 to the next line in Word's print as every other contents line; its held tab broke the line's
            // strut and stood it on Calibri's 11pt line, 25.89. Shaded, it keeps its box to paint the shade.)
            if theme.wordRules, ch == "\t", s.fontSize ?? 0 > 0.5, !RichLayout.shadeShows(run.highlight),
               p.text.contains(where: { !$0.isWhitespace && $0 != "\u{FFFC}" }),
               RichLayout._tabBiggerThanText(run.fontSize ?? named?.char.fontSize ?? theme.fontSize, p, named?.char.fontSize ?? theme.fontSize) {
                RuleTrace.hit("held-tab-sets-no-line-beside-text")
                heldStyle = heldStyle.copyWith(height: 0.01)
            }
            spans.append(TextSpan(text: "\u{00A0}", style: heldStyle))
        }
        start = after
        ctx.afterHeld = !koreanSpaces.contains(offset)
        ctx.heldKind = kind
    } else if theme.wordRules, let u = ch.unicodeScalars.first?.value,
              [0x2000, 0x2001, 0x2004, 0x2006, 0x2008, 0x2009, 0x200A, 0x205F].contains(u) {
        // (Word does not part a line at these spaces — lab `spaces`, in a body
        // paragraph and a fixed cell alike: only U+2002, U+2003, U+2005, U+3000, the
        // space and the zero-width space are places to break; the others are held
        // like a no-break space, of their own width.)
        flush(i)
        let s = style(kind)
        spans.append(TextSpan(text: "\u{00A0}", style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra + _glyphWidth(s, ch) - _glyphWidth(s, "\u{00A0}"))))
        start = after
    } else if theme.wordRules, let u = ch.unicodeScalars.first?.value, u >= 0xE000, u <= 0xF8FF,
              let w = latinFace?.missingGlyphAdvance {
        // (A private-use character no face has is the run's
        // face's missing-glyph box, blank: bug59058's formulas
        // hold U+E037/E038 from an HTML converter, 10.11pt
        // each at 13pt in Word's print — Times' .notdef, 0.7778
        // em — where a fallback drew a glyph near twice that
        // and pushed every formula past the line.)
        flush(i)
        let s = style(kind)
        // (A no-break space: the box is no place to part a line.)
        spans.append(TextSpan(text: String(ch), style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra + w * em - _glyphWidth(s, ch))))
        start = after
    } else if theme.wordRules, !ea, let u = ch.unicodeScalars.first?.value, u >= 0x25A0, u <= 0x25FF,
              (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily)?.lowercased() == "times new roman" {
        // (A geometric shape in a Times New Roman run is that
        // face's — Word's Times New Roman has "○", the stand-in
        // has not; where Word's Latin face lacks it, Word falls
        // back to YaHei as ours does, zh-454e2e29's "○" and "△",
        // and the platform's fallback, a CJK face, made the line
        // its own: zh-cec9d337's 22pt "○" cells on an 18pt grid
        // are two pitches in Word's print, 36pt, and ours 37.8
        // a row, the table's last row going over. Its line asks
        // an em at most — off the grid. On it, the line is the
        // Times line the grid snapped: lab `g44` in zh-cec9d337's
        // package (Word 16, 2026-10-18), a row of these at 14pt
        // is its 28.3pt "at least", at 18 and 22pt two pitches,
        // 36.5, where ours, held to the em after the grid had
        // snapped it, stood 28.25 at every size.)
        flush(i)
        let s = style(kind)
        let height = pitch != nil && s.height != nil ? s.height : min(s.height ?? 1, 1.0)
        spans.append(TextSpan(text: String(ch), style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra, height: height)))
        start = after
    } else if theme.wordRules, let u = ch.unicodeScalars.first?.value,
              (u >= 0x1D400 && u <= 0x1D7FF) || (u > 0x7F && latinFace?.setsMath == true && !ea) {
        // (A mathematical letter, which no shipped face has,
        // comes from the platform's math face — STIX Two Math
        // on a Mac, 0.762 above and 0.238 below with a quarter
        // em of leading — whose own split of the run's height
        // set bug59058's formula lines 16.4pt apart where
        // Word's, in Cambria Math, are 15.2. At four fifths of
        // the run's height it sits inside the line the text
        // makes; its glyphs stand on the same baseline.)
        flush(i)
        let s = style(kind)
        spans.append(TextSpan(text: String(ch), style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra, height: (s.height ?? 1) * 0.6)))
        start = after
    } else if ea, theme.wordRules, let u = ch.unicodeScalars.first?.value,
              [0x25B2, 0x25B3, 0x25BC, 0x25BD, 0x2605, 0x2606].contains(u),
              let symbols = theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                                ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)
                  .flatMap({ face in face.symbolsInBold || !(run.bold || (named?.char.bold ?? false) && !run.off.contains(.bold)) ? face.symbolFamily : nil }) {
        // (A triangle or star in a face Word lacks is SimSun's,
        // and so is its line — circles and squares are YaHei's
        // own in Word's prints, zh-7dc3afad's ○ and □: lab `tr2`, zh-6cd1befe's "▲" in
        // 12pt 仿宋_GB2312 on a 15.6pt grid takes one pitch in
        // Word's print, where YaHei's line took two and every
        // row of its task table stood 5pt tall.)
        flush(i)
        var r = run
        r.eastAsiaFontFamily = symbols
        let s = theme.textStyle(for: r, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                eastAsian: true, gridPitch: pitch)
        spans.append(TextSpan(text: String(ch), style: extra != 0 ? s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra) : s))
        start = after
    } else if ea, theme.wordRules, (style(kind).fontWeight == .bold || theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.otherAdvances?[0x2160] == nil), let cjk = RichLayout._cjkFaceFamily, let u = ch.unicodeScalars.first?.value, (0x2160 ... 0x217F).contains(u) || u == 0x25C8 {
        // (A Roman numeral in East Asian text is the CJK face's,
        // an em wide: zh-78729cf9's "（Ⅰ级）、重大（Ⅱ级）" in a
        // hinted 仿宋_GB2312 run is YaHei's in Word's print, each
        // numeral a full cell. The Latin stand-in has none, and
        // the fallback found DejaVu's, 0.34 to 0.73 em: the line
        // took a character more than Word's, three times.)
        flush(i)
        let s = style(kind)
        var numeral = (extra != 0 ? s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra) : s).copyWith(fontFamily: cjk)
        #if os(Linux)
        // (Linux's CJK face may be absent, and the glyph then
        // the fallback's, 4.7pt where Word's print has the
        // 仿宋_GB2312 numeral a full 16: zh-94f12659's "（Ⅰ级）"
        // kept "故：" on a line Word wrapped. Pad to the cell.)
        numeral = numeral.copyWith(letterSpacing: (numeral.letterSpacing ?? 0) + max(0, em - _glyphWidth(numeral, ch)))
        #endif
        spans.append(TextSpan(text: String(ch), style: numeral))
        start = after
    } else if !ea, theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, ((0x2010 ... 0x2027).contains(u) || (0x2030 ... 0x205E).contains(u)), u != 0x2011, latinFace?.isEastAsian != true, !run.formBox,
              // (General Punctuation only, not the invisible format marks U+2028-202F and U+205F-206F (the engine's own word joiner U+2060 is one): Word's prints draw math and enclosed symbols (⌈ ① in 0d8cbc, 27083953) in Cambria Math, and U+2011 as a plain hyphen, not in the East Asian face; a form check box is a drawn box. A mark the run's Latin face lacks, by that face's cmap (RichLayout._latinSymbolCmap, from the Windows Word box); a face not in the table keeps only ※.)
              RichLayout._latinFaceLacks(run.fontFamily ?? named?.char.fontFamily ?? "", u) ?? (u == 0x203B),
              let cjk = RichLayout._cjkFaceFamily {
        // (The reference mark ※ in a run whose Latin face lacks it is the East Asian
        // face's in Word's print, a full cell: jpn-z21601833-463426's Cambria italic
        // "※ ..." paragraphs draw it in MS Mincho, 12pt, where our fallback gave
        // 10.1 and its line stood about 1pt short.)
        flush(i)
        let s = style(kind)
        var mark = (extra != 0 ? s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra) : s).copyWith(fontFamily: cjk)
        mark = mark.copyWith(letterSpacing: (mark.letterSpacing ?? 0) + max(0, em - _glyphWidth(mark, ch)))
        // (A line holding it is MS Mincho's: 1.2969 em, split 0.859 / 0.141 as the face's own ascent and descent, in the 463426 print.)
        if devanagariStyles["eaMark"] == nil {
            devanagariStyles["eaMark"] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: 0.859 * 1.2969, descent: 0.141 * 1.2969)
        }
        if let joiner = devanagariStyles["eaMark"] ?? nil {
            spans.append(TextSpan(text: "\u{2060}", style: joiner))
            ctx.inserts.append(offset)
        }
        spans.append(TextSpan(text: String(ch), style: mark))
        start = after
    } else if ea, theme.wordRules, RichTextTheme.wordWindowsPages, ch == "\u{203B}", let cjk = RichLayout._cjkFaceFamily,
              { let n = (run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily ?? ""); let l = n.lowercased()
                  return l.containsSubstring("meiryo") || l.containsSubstring("ms gothic") || l.containsSubstring("ms mincho") || l.containsSubstring("ms pgothic") || l.containsSubstring("ms pmincho")
                      || l.containsSubstring("yu gothic") || l.containsSubstring("yu mincho") || n.containsSubstring("メイリオ") || n.containsSubstring("ＭＳ") || n.containsSubstring("游") }() {
        // (The reference mark ※ in a Japanese East Asian run (not a Chinese face: dx2 zh-ae2dd08d's DFKai-SB ※ went down) is the East Asian face's own (Meiryo, MS Gothic: 5d7ee6's prints show MS-Gothic), an em wide, as the ☆ and the fullwidth digit beside it:
        // dx2 934bd3e5's superscript "※１" is 7.0pt apiece in Word's print, where our DejaVu fallback gave 7.9
        // for the mark and its lines broke a character early.)
        flush(i)
        let s = style(kind)
        let mark = (extra != 0 ? s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra) : s).copyWith(fontFamily: cjk)
        spans.append(TextSpan(text: String(ch), style: mark.copyWith(letterSpacing: (mark.letterSpacing ?? 0) + max(0, (mark.fontSize ?? em) - _glyphWidth(mark, ch)))))
        start = after
    } else if ea, theme.wordRules, ch == "\u{02D9}" {
        // (A dot above in East Asian text is a full cell: the
        // Bopomofo tone mark of Taiwan's faces, 標楷體's among
        // them, an em wide in Word's print as zh-ab34d9cb's "˙"
        // bullets are, 14pt apiece where the stand-in's Latin
        // fallback gave 4.7 and each such line took a character
        // more than Word's.)
        flush(i)
        let s = style(kind)
        let width = _glyphWidth(s, ch)
        spans.append(TextSpan(text: String(ch), style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra + max(0, em - width))))
        start = after
    } else if ea, theme.wordRules, let cjk = RichLayout._cjkSymbolFamily, RichLayout._cjkSymbols.contains(ch) {
        // (A dash or an ellipsis in East Asian text is the
        // CJK face's glyph, with its metrics: the Latin
        // stand-in the East Asian style is built on has one
        // too, and its ascent and descent split the em
        // otherwise, so a line with it grew — zh-90e0cea8's
        // header "DB 37/T 4497—2022" stood 1.1pt taller than
        // Word's, and its pages' text that much lower.)
        flush(i)
        let s = style(kind)
        spans.append(TextSpan(text: String(ch), style: (extra != 0 ? s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra) : s).copyWith(fontFamily: cjk)))
        start = after
    } else if extra != 0 {
        flush(i)
        // (A space the fit cut out of its run is set at the size the run's other spaces take: a Windows Latin face's own, not the Indic stand-in's, 4% wider. The fit loop counts 3.33 pt and the engine set 3.6, so a squeeze of 0.59 pt delivered 0.31 and 1116b68d's last word never fitted.)
        var s: TextStyle
        if ch == " ", kind >= 0, indic != nil, run.fontFamily != nil || indic?.face == "nirmala ui", theme.wordRules, RichTextTheme.wordWindowsPages,
           p.text.unicodeScalars.contains(where: { ($0.value >= 0x905 && $0.value <= 0x939) || ($0.value >= 0xA05 && $0.value <= 0xA39) }) {
            latinNoScale = true
            s = style(kind)
            latinNoScale = false
        } else {
            s = style(kind)
        }
        // (A space the fit gives to is set at Kokila's own width as every other space of the run is: split out of its run it would take
        // the stand-in's, narrower, and the engine would find room the fit loop never counted. f0001d05 line 3.)
        if ch == " ", kind >= 0, indic?.face == "kokila", kokilaLatin, let px = s.fontSize, px > 0.5, RichLayout._indicLines["kokila"] != nil {
            s = _kokilaLatinStyle(" ", base: s, px: px)
        } else if ch == " ", kind >= 0, indic?.face == "shonar bangla", let px = s.fontSize, px > 0.5 {
            // (Shonar Bangla's own space, 0.2065 em, for a space the fit cut out of its run.)
            let authored = (run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
            s = _indicSpaceStyle(base: s, spaceEm: 0.2065, unit: authored)
        } else if ch == " ", kind >= 0, let face = indic?.face, face != "kokila",
                  // (A space the fit cut out of a danda-and-space run in a missing Bengali face: the fit's extra IS its pad up to Mangal's half em (lab left0, 60.3 units), so the pad is not added a second time: the space was 8.5 pt, 5.5 in Word.)
                  !(extra != 0 && RichLayout._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") != nil),
                  let spaceEm = (face == "vrinda" && (run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold)))) ? 0.3125 : RichLayout._indicSpace[face],
                  let px = s.fontSize, px > 0.5 {
            // (The same for the faces whose space is their own, Mangal, Vrinda, Utsaah: one path, `_indicSpaceStyle`.)
            let authored = RichLayout._wordGridSize(run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize, snap: face == "mangal" && theme.wordRules && RichTextTheme.wordWindowsPages) * theme.pixelsPerPoint * scale
            // (A space a justified line cut out of an Arial run drawn in Mangal only because the document's first Devanagari run names it keeps Arial's 0.278 em.)
            let arialSpace = face == "mangal" && document.devanagariFirstRunMangal && (run.fontFamily ?? "").trimmingWhitespace().lowercased() == "arial"
            s = _indicSpaceStyle(base: s, spaceEm: arialSpace ? 0.2778 : spaceEm, unit: face == "mangal" ? authored : px)
        }
        if theme.wordRules, ch == "\u{00A0}" {
            // (A no-break space's width on a word joiner after
            // it: the engine sets no spacing on the space
            // itself — zh-17749c13's "第十三条  受理…", 宋体
            // no-break spaces an em apiece in Word's print, came
            // out at the stand-in's 0.29 em with the em's
            // spacing on them.)
            spans.append(TextSpan(text: "\u{00A0}", style: s))
            spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(kind).copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra)))
            ctx.inserts.append(offset + 1)
        } else if theme.wordRules, ea, ch == "\u{2013}" {
            // (So too an East Asian dash the East Asian face
            // lacks, drawn by the glyph fallback: its own
            // spacing came out only before a space — lab `ds`,
            // PMingLiU's em-wide "–" stood 6.67 before "基",
            // 12.0 before " ".)
            spans.append(TextSpan(text: String(ch), style: s))
            spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(kind).copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra)))
            ctx.inserts.append(offset + 1)
        } else {
            // (The engine spaces every glyph, so a Thai letter
            // drawn with its marks as several takes its share
            // on each: Cordia's "คำ" is three glyphs, and the
            // 0.5pt it wanted made zh-6a4fc013's every "คำ"
            // 1.5 wider; "คำถามที่ 4 ：" ran a point long and
            // sent its question to the next line.)
            if extra < 0, let px = s.fontSize, px > 0.5, let u = ch.unicodeScalars.first?.value, u >= 0x3000, u < 0xFF60 {
                let g = _glyphWidth(s, ch)
                if g > 0.9 * px, g + extra < 0.6 * px {
                    let h = s.copyWith(fontFeatures: (s.fontFeatures ?? []) + [FontFeature("halt", 1)])
                    let gh = _glyphWidth(h, ch)
                    if gh < 0.6 * px { extra += g - gh; s = h }
                }
            }
            var spacing = (s.letterSpacing ?? 0) + extra
            // (And any character past ASCII the face draws in
            // pieces: on the Mac the fallback for zh-d97c5474's
            // Cambria Greek sets "ή", "ό" as a letter and an
            // accent, and each took Cambria's width correction
            // twice — its lines 1.7% short, a word more each.)
            if theme.wordRules, extra != 0, let u = ch.unicodeScalars.first?.value,
               (u >= 0x0E00 && u < 0x0E80 && ch.unicodeScalars.count > 1) || (u >= 0x80 && !(0x0E00 ..< 0x0E80).contains(u)) {
                spacing /= Double(_glyphCount(s, ch))
            }
            spans.append(contentsOf: capped(text[i ..< after], run, s.copyWith(letterSpacing: spacing)))
        }
        start = after
    }
    }
}
