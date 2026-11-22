// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "StyledSblk1": a step of the styled loop

import Flutter
import FlutterSwiftBridge
import Foundation

extension _StyledFrame {
    @inline(never) func _sblk1() {
    if ctx.afterHeld, ch != " ", !(breaksAtQuotes && !lineRulesOff && RichLayout._closingMarks.contains(ch)) {
        flush(i)
        // (In the held spaces' own style, not the East Asian
        // text's after them: there its glyph is the Latin base
        // family's, whose ascent and descent split the em
        // otherwise than the CJK face's, and the line grew
        // 0.9pt at 12pt — zh-799c91cd's page 1 lost a line.)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(ctx.heldKind ?? current ?? kind)))
        ctx.inserts.append(offset)
        ctx.afterHeld = false
    } else if !theme.wordRules, theme.officeLatinBreaks, p.style.eastAsian["a:eaLnBrk"] != "0", let b = ctx.before, RichLayout._slidesBreaksBetween(b, ch) {
        // (PowerPoint, with East Asian line breaking on (eaLnBrk, the default), may wrap between any two ideographs or kana
        // unless kinsoku forbids it: 44a22c19 p15 wraps 収|入, 財|産, でしょ|うか. The engine's dictionary keeps a word whole.)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
        ctx.inserts.append(offset)
    } else if !theme.wordRules, theme.officeLatinBreaks, ch == "？", p.style.eastAsian["a:eaLnBrk"] != "0", let b = ctx.before, b.unicodeScalars.count == 1, let bv = b.unicodeScalars.first?.value, bv >= 0x3041 && bv <= 0x9FFF {
        // (PowerPoint lets a full-width "？" begin a line after kana or an ideograph: e89e63a8 p6's title "…体制は？" in a 675pt box ends its line on "は" and prints the "？" alone on the next, where the engine's rules kept "は？" together.)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
        ctx.inserts.append(offset)
    } else if !theme.wordRules, theme.officeLatinBreaks, ctx.before == "+", let v = ch.unicodeScalars.first?.value, v >= 0xAC00, v <= 0xD7A3 {
        // (PowerPoint parts a line after a "+" before a Hangul syllable, where the engine kept the sign with what it prefixes: ko-e114b968 p20's
        // header "매우그렇다+그렇다(%)" in a narrow cell is "매우" | "그렇다+" | "그렇다(%)" in the print, ours "+그렇다" down.)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
        ctx.inserts.append(offset)
    } else if !theme.wordRules, theme.officeLatinBreaks, ch == "(", let b = ctx.before, let v = b.unicodeScalars.first?.value, v >= 0xAC00, v <= 0xD7A3 {
        // (And keeps an ASCII "(" with the Hangul syllable before it: the same header's "그렇다(%)" stays whole.)
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if !theme.wordRules, theme.officeLatinBreaks, let b = ctx.before, ch.unicodeScalars.count == 1, "ぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶー".contains(ch), p.style.eastAsian["a:looseKinsoku"] != "1",
              b.unicodeScalars.count == 1, let bv = b.unicodeScalars.first?.value, bv >= 0x3041 && bv <= 0x9FFF {
        // (PowerPoint keeps small kana and the prolonged sound mark with the kana or ideograph before them under strict kinsoku, the default (a deck with strictFirstAndLastChars 0 opens lines with them: ff27a386 p8 "ウ" | "ェールズ"): e89e63a8 p6's
        // "こども支援センター" in a 177pt box goes down as "セン" | "ター" in the print, where the engine's loose rules took "センタ" | "ー".)
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if !theme.wordRules, theme.officeLatinBreaks, ctx.before == "-", ch.isASCII, ch.isNumber,
              ctx.beforeBefore.map({ $0.isASCII && ($0.isLetter || $0.isNumber) }) == true {
        // (PowerPoint ends a line after a hyphen that stands between a letter or digit and a digit: ba4b81b7's
        // "IDs 1M-2M" and "14M-15M" print "1M-" and "2M" on two lines. The engine's rules (UAX 14) keep "-" and a digit together.)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, (ctx.before == "\u{2014}" && ch.isASCII && ch.isNumber && ctx.beforeBefore.map { $0.isASCII && $0.isNumber || RichLayout._closingMarks.contains($0) } == true)
                || (ch == "\u{2014}" && !ea && ctx.before.map { $0.isASCII && $0.isNumber } == true && following.map { $0.isASCII && $0.isNumber } == true)
                || (RichTextTheme.wordWindowsPages && ch == "\u{2014}" && !ea && ctx.before.map { $0.isASCII && $0.isLetter } == true) {
        // (… nor after one that follows a closing bracket, before digits: zh-22ecbdc8's
        // "…达1000（含）" / "—5000人/年" in Word's print, and lab legsq's "（含）—5000" taken or
        // left whole; ours parted "—" from "5000". Word's prints end a line on "—" with digits
        // after it 3 times in the corpus, none after a bracket.)
        // (Nor on either side of an em dash between digits — a span
        // of years: zh-b378d8c4's "（2021—2030年）" goes down whole
        // in Word's print, its "（" unable to end a line; the
        // engine parted it at the dash.)
        // (Before the dash, a Latin dash only, as that one is, in
        // Times: one set in the East Asian face, hinted so, may open
        // a line, the digits after it kept with it — zh-8d6f702e's
        // and zh-c2f6d17a's "…面雨量达100" / "—150毫米" in Word's
        // print, where ours took "100—150" down whole, and
        // zh-81a32de0's "…以上。（1" / "—5分）". Lab `dash` (Word for
        // Windows, zh-8d6f702e's package): the same "—" hinted
        // default in Times goes down with "100—150", with or without
        // `doNotUseEastAsianBreakRules`; the face decides.)
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, RichTextTheme.wordWindowsPages, ctx.before == " ", ch == "/" {
        // (Unicode forbids a break before "/" even after a space,
        // so the engine backed up a word; Word breaks there, in
        // Korean, Latin and Chinese alike (lab slash, 4 prints).
        // kor-z15852510-c9baf7's `가짐." />` keeps `가짐."` and
        // sends "/>" down.)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, breaksAtQuotes, !lineRulesOff, ctx.before == " ", RichLayout._closingMarks.contains(ch) {
        // (Nor before a closing mark after spaces, which may no
        // more start a line there than anywhere: zh-f47b8a74's
        // "…将罚款缴至" and 19 underlined spaces, then "，账号",
        // go down whole in Word's print, "至" opening the line;
        // the engine broke after the spaces, and the line after
        // began with the "，".)
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if RichTextTheme.wordWindowsPages, theme.wordRules, ea,
              (ctx.before == "\u{2014}" && ch == "\u{2014}")
                || ((ch.unicodeScalars.first?.value).map { 0x2260 ... 0x226F ~= $0 } == true
                    && ctx.before.map { $0.isASCII && ($0.isLetter || $0.isNumber) } == true) {
        // (A line may break between the two dashes of an East Asian "——", and
        // before a mathematical sign set as East Asian after Latin letters or
        // digits, Word for Windows: zh-447f1d5c's "…准则5号—" / "—公共基础设施》"
        // and zh-0060058e's "…中型排水管道（600mm" / "≤管径＜1000mm）" in Word's
        // print, both runs hinted East Asian (the comparison signs only: zh-0978dee9's
        // ratio "6∶3∶1" stays whole); the engine kept "——" whole and
        // "600mm≤管径" together, and carried both down.)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if RichTextTheme.wordWindowsPages, theme.wordRules, ch == "/", let b = ctx.before, "）」』】〉》〕］｝".contains(b) {
        // (A line may break between a full-width closing bracket and a "/", Word for
        // Windows: zh-6e7ff836's cell formula "…實際數平均值）/ 前3年…" ends a line
        // "…平均值）" in Word's print, the "/" opening the next; the engine, which never
        // breaks before a slash, squeezed the "）" to keep "值）/" on the line.)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if RichTextTheme.wordWindowsPages, theme.wordRules, ch == "\u{FE6A}", ctx.before.map({ $0.isASCII && $0.isNumber }) == true {
        // (A line may break between a digit and the small percent
        // sign "﹪", which is no Latin "%": zh-146f4e02's "…價值）的8﹪給予"
        // ends a line "…的8" in Word for Windows' print, the "﹪"
        // opening the next (six such lines); the engine keeps a
        // number with its percent sign and carried the "8" down.)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, ctx.before == "-", ch.isASCII, ch.isNumber,
              (ctx.wordHasLetter && ctx.beforeBefore.map { $0.isASCII && ($0.isLetter || $0.isNumber) } == true)
                || ctx.beforeBefore.map { !$0.isASCII && RichLayout.isEastAsian($0, hinted: false) } == true {
        // (A line may break after a hyphen before a digit, as
        // after one before a letter: zh-15f60bac's "…公布之
        // CNS11643-2(中文字基礎部件…" ends a line "CNS11643-" in
        // Word's print and starts the next "2(中文字"; the
        // engine, by Unicode's rules, keeps a hyphen with the
        // number after it, and took "CNS11643-2" down whole.
        // Not in a number alone: zh-64044a1d's narrow cells set
        // "0932-757839" as "0932-75783" and "9", a telephone
        // number parted where it fills the line, not at its
        // hyphen; nor zh-dd4c6e05's "（110-116", a span of years,
        // which Word keeps whole — while its "（110 年-114 年）"
        // ends a line "年-": a hyphen after an ideograph.)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, !lineRulesOff, ctx.before == " ",
              ch == "%" || ch == "‰" || ch == "℃" || RichLayout._closingMarks.contains(ch) {
        // (Nor after spaces before a mark no line may start
        // with: Word goes back to the break before them.
        // zh-f43c9edf's "提取    %作为…" — a blank to fill in —
        // ends a line "提" and starts the next "取    %" in
        // Word's print; the engine parted it at the spaces and
        // opened the line with "%".)
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if traditionalLists, !lineRulesOff, ch == "\u{FF05}", let b = ctx.before, b.isASCII, b.isNumber {
        // (Before a full-width percent sign after a number, where
        // Word's Traditional Chinese lists hold: they do not keep
        // "％" from a line's start, as its Simplified one does.
        // zh-499adba6's "…占比為38.54" ends page 25's first line
        // in Word's print and "％，女性理事…" opens the next;
        // the engine, by Unicode's rules, keeps a number's sign
        // with it, took "38.54％" down and set every line after
        // two characters behind.)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if RichTextTheme.wordWindowsPages, theme.wordRules, (document.compatibilityMode ?? 12) >= 15, ch == "\u{30FB}", document.hasKana,
              document.eastAsiaLanguage?.hasPrefix("ja") != true, let b = ctx.before, (b.unicodeScalars.first?.value ?? 0) >= 0x3040, !RichLayout._openingMarks.contains(b) {
        // (Word for Windows opens a line with the katakana middle dot at compat 15 in kana text tagged
        // zh-CN: 8787f4 p8 ends "…リスクテイク" and starts "・高速な…", 4 lines so; the engine keeps it with the character before.)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
        ctx.inserts.append(offset)
    } else if plainNoLineRules, document.hangsLatinStops, ctx.latinAfterEastAsian, let b = ctx.before, b.isASCII, !ctx.latinRunBracket || ch == "/", b.isLetter || b.isNumber || b == ".", (ch.isASCII && (ch.isLetter || ch.isNumber || ch == "/") || ch == "\u{2192}") {
        // (The same file breaks a Latin run that follows East Asian text with no space anywhere
        // inside it: jpn-z21601833-4e6465 ends lines "…DA|G」", "…（rev|27", "…三角形数＝2E|/3。"
        // and starts "/450）"; a run opened by a space stays whole: "…厳密に E/3。".)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
        ctx.inserts.append(offset)
    } else if plainNoLineRules, ch == "\u{30FB}", let b = ctx.before, (b.unicodeScalars.first?.value ?? 0) >= 0x3040, !RichLayout._openingMarks.contains(b) {
        // (A plain file with no line rules (Pandoc's en-US) opens a line with the middle dot too:
        // jpn-z21601833-4e6465 p6 ends "…完全な終了" and starts "・完全な静止を取らない".)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
        ctx.inserts.append(offset)
    } else if !theme.wordRules, ch == ")", let b = ctx.before, let v = b.unicodeScalars.first?.value, v >= 0x3040, v <= 0x9FFF {
        // (PowerPoint lets an ASCII ")" after kanji or kana open a line, where after Hangul it hangs: lab hang3 slide 6 keeps
        // "学校教育課程" and moves the ")" down below 127.03 pt; Unicode's no-break before it carried the kanji down with it.)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
        ctx.inserts.append(offset)
    } else if pausesOpenLines, ch == "\u{3001}" || ch == "\u{3002}" || ch == "\u{FF09}", let b = ctx.before, !RichLayout._closingMarks.contains(b) {
        // (A full-width ")" too: 8787f4 p8 ends "…（ドーシ, 1982" and opens the next line with "）。".)
        // (Where the pause rule holds Word opens a line with 、 or 。 rather than
        // hang it or carry the character before it down: lab `sqreal`.)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
        ctx.inserts.append(offset)
    } else if RichTextTheme.wordWindowsPages, theme.wordRules, (document.compatibilityMode ?? 12) == 14, document.characterSpacingControl == "compressPunctuation",
              document.markSqueezeEm == 0, ch == "\u{FF0C}" || ch == "\u{3001}" || ch == "\u{3002}", let b = ctx.before, !RichLayout._closingMarks.contains(b) {
        // (Under compressPunctuation at compat 14 with no language or ko-KR, whose marks Word never
        // squeezes (glyph advances 12.0 of 12.0 and 16.0 of 16.0, lab comma-hang7 v6/v8), Word opens
        // a line with the mark rather than hang it or carry the character before it down.)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
        ctx.inserts.append(offset)
    } else if (kinsokuOff || plainNoLineRules || (theme.wordRules && (ch == "\u{3001}" || ch == "\u{3002}") && !hanJoins.contains(offset) && RichLayout._dunhaoMayStart(run, document, named: named)) || (RichTextTheme.wordWindowsPages && theme.wordRules && document.defaultLangXML == nil && document.eastAsianDefaultFaceIsLatin && (!document.bodyStatesLang || !RichLayout._runStatesLang(run, named)))) && !breaksAtQuotes, let b = ctx.before,
              RichLayout._closingMarks.contains(ch) || RichLayout._latinCloser(b, ch) || RichLayout._plainMayStart(b, ch)
                || (ch != " " && (RichLayout._openingMarks.contains(b) || RichLayout._latinOpener(b, ch))
                    && RichLayout._plainOrKinsoku(plainNoLineRules, kinsokuOff, RichLayout._eastAsianLineRules(run, document, named: named)) && RichLayout._plainOpenerBreak(plainNoLineRules && !kinsokuOff && !openerBeforeLatin, ch)) {
        // The paragraph's explicit kinsoku=0 works without
        // useFELayout too: fresh Word's comma/parenthesis controls
        // have identical breaks with that switch on and off.
        // Keep the other FE-layout break opportunities separate.
        // This synthetic break has no line metrics: its Latin
        // stand-in otherwise enlarges a mixed-size FangSong line
        // (zh-202582e2 p5) despite having no glyph to draw.
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
        ctx.inserts.append(offset)
    } else if RichTextTheme.wordWindowsPages, theme.wordRules, (document.compatibilityMode ?? 12) >= 15, p.style.alignment == .justify, !kinsokuOff, ch != " ", let b = ctx.before,
              document.hasKana || document.eastAsiaLanguage?.hasPrefix("ja") == true, RichLayout._openingMarks.contains(b), document.characterSpacingControl?.hasPrefix("compressPunctuation") ?? false,
              (ch.unicodeScalars.first?.value ?? 0) >= 0x2E80, adjust[-(offset + 1)] == nil {
        // (Under compressPunctuation Word may end a line on an opening
        // mark, squeezed by up to half its em: labs opn1 and opn11, 8787f4.
        // The fit decides, and a mark it would carry gets the key -(offset+1).)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
        ctx.inserts.append(offset)
    } else if breaksAtQuotes, let b = ctx.before, !(RichLayout._closingQuote(ch) && b.isASCII && b != " " && b != "\n"),
              // (A closing quote right after an ASCII character is no break, whatever the East Asian
              // rules say: xa gv-690391482c (en-GB East Asian language, usesEastAsianLayout) keeps
              // "individuals.”" whole in Word's print, ours sent the quote down alone.)
              RichLayout._breaksBetween(b, ch, percentStarts: percentStarts, timesEastAsian: hinted, shapesPart: (document.compatibilityMode ?? 12) >= 15 || RichTextTheme.wordWindowsPages, latinQuotes: theme.wordRules && !hinted) || (lineRulesOff && !(RichLayout._hangulSyllable(b) && (ch == ")" || ch == "." || ch == "," || ch == "]")) && (RichLayout._closingMarks.contains(ch) || RichLayout._latinCloser(b, ch)))
                || (theme.wordRules && RichLayout._closingQuote(ch) && !(b.unicodeScalars.first.map { (0x0E01 ... 0x0E5B).contains($0.value) } ?? false) && (kinsokuOff && hinted && RichTextTheme.wordWindowsPages || !RichLayout._eastAsianLineRules(run, document, named: named)))
                // (And end one with an opening mark, where it is
                // `w:kinsoku` 0 that turns them off in text of an
                // East Asian language: zh-72da925e (zh-TW) ends
                // a line "…（下稱「" in Word's print, "中" opening
                // the next. Not where the language is not one —
                // zh-c5b5087b's en-US carries "（" over.)
                || ((kinsokuOff || plainNoLineRules) && ch != " " && (RichLayout._openingMarks.contains(b) || RichLayout._latinOpener(b, ch)) && RichLayout._plainOrKinsoku(plainNoLineRules, kinsokuOff, RichLayout._eastAsianLineRules(run, document, named: named)) && RichLayout._plainOpenerBreak(plainNoLineRules && !kinsokuOff && !openerBeforeLatin, ch))
                // (A full-width opening quote the same: zh-b00fef0d's "…其中" sends "“1" down whole,
                // the quote unable to stay alone at the line's end 12pt over.)
                || (kinsokuOff && RichTextTheme.wordWindowsPages && ch != " " && (b == "\u{201C}" || b == "\u{2018}") && runHinted(atOffset: offset - 1) && RichLayout._eastAsianLineRules(run, document, named: named))
                // (In a line too narrow for one character
                // every character is a line, the marks
                // too: zh-830ef10d's 6pt cell sets
                // "个性要求（6分）" one to a line in Word's
                // print, "（" and "6" and "分" and "）" each
                // alone, where ours kept "（6" and "分）".)
                || (b != "\n" && textWidth > 0 && textWidth < (style(kind).fontSize ?? 0)) {
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    }
    }
}
