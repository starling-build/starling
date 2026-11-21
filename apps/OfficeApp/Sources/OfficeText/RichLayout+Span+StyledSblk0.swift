// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "StyledSblk0": a step of the styled loop

import Flutter
import FlutterSwiftBridge
import Foundation

extension _StyledFrame {
    @inline(never) func _sblk0() {
    if ctx.wideStarts.contains(offset) {
        // (A word wider than the line opens a line of its own,
        // and is parted there: see `_wideWordStarts`.)
        flush(i)
        spans.append(TextSpan(text: "\u{2029}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if ctx.loose.contains(offset) {
        flush(i)
        // (A word wider than the line parted at a hyphenation
        // point ends its line there with the hyphen drawn.)
        if !ea, let idx = index, _hyphenPoints[idx]?.contains(offset) == true {
            spans.append(TextSpan(text: "-", style: style(kind)))
        } else {
            spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
        }
        ctx.inserts.append(offset)
    } else if let idx = index, let points = _hyphenPoints[idx], points.contains(offset), !ea {
        // (Automatic hyphenation: a place the word may be parted
        // at, with the hyphen drawn where the line does end.)
        flush(i)
        if _hyphenShown[idx]?.contains(offset) == true {
            spans.append(TextSpan(text: "-", style: style(kind)))
        } else {
            spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
        }
        ctx.inserts.append(offset)
    } else if ctx.rubyHeld.contains(offset) {
        // (A ruby group is not parted by a line end: Word's column in 934bd3e5 p3 ends at "ありけるに、" and sets the
        // whole of 小式部内 on the next, where ours took 小式 and split the reading, every later column two late.)
        RuleTrace.hit("word-ruby-group-holds-its-base")
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, !document.usesEastAsianLayout, ctx.spacesAfterNbsp, ctx.before == " ", !ea,
              !ch.isWhitespace, ch != "\u{00A0}" {
        // (Plain spaces after a no-break space hold the word
        // that follows them: Word parts no line between
        // "X)" + U+00A0 + U+0020 and the next word, so one
        // wider than what is left of the line is cut where the
        // line ends. LibreOffice's tdf134606, "X)\u{00A0} XXXXXXXXXXXX"
        // in a 94pt cell: Word sets "X)  XXXXXXXXXXX" / "X
        // XXXXXXXXX *", ours sent the 12 X's down whole, a
        // third line, the row 12pt taller.)
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, RichTextTheme.wordWindowsPages, ch == "\u{00A0}", ctx.before == "\u{0964}" || ctx.before == "\u{0965}" {
        // (A danda may part from a no-break space after it in the break table (it allows a break after the mark), and Word does
        // not: xd 73caaeda's "…ক্রুসেড।" + U+00A0 + "Toledo" + U+00A0 + "(১০৮৫)," goes down to the next line as one piece, the
        // danda with it, where ours left it at the end of the line above.)
        RuleTrace.hit("word-no-break-space-after-a-danda-holds-it")
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, RichTextTheme.wordWindowsPages, (ctx.before == "." && ch == "." && !(RichLayout._stopRunFitsAfterSpace(Array(p.text.utf16), at: offset, measure: { run in let t = TextPainter(text: TextSpan(text: run, style: style(kind)), textDirection: .ltr); t.layout(minWidth: 0, maxWidth: 100_000); defer { t.dispose() }; return t.width }, width: _px(textWidth))) && !(RichLayout._stopRunAfterWordFits(Array(p.text.utf16), at: offset, measure: { run in let t = TextPainter(text: TextSpan(text: run, style: style(kind)), textDirection: .ltr); t.layout(minWidth: 0, maxWidth: 100_000); defer { t.dispose() }; return t.width }, width: _px(textWidth)))) || (!document.usesEastAsianLayout && (ctx.before == "…" || ch == "…") && (ctx.before == "." || ctx.before == "…") && (ch == "." || ch == "…") && RichLayout._stopRunWidth(Array(p.text.utf16), at: offset, size: style(kind).fontSize ?? 12) > textWidth), document.usesEastAsianLayout || !ctx.dotsAttached {
        // (Not stops that follow a word's letters, in a file that sets no East Asian
        // layout: bede0fbc's "নাম:" + 154 stops is one word, which Word sends down
        // whole when it fits a line of its own, and parts only if it cannot.)
        // (A run of stops parts between any two of them, and fills each
        // line to capacity: zh-92373179 p11's dot leader row, where the
        // engine held the run whole and Word sets 4 + 1. Lab dot-run:
        // even one stop alone goes down to the next line.)
        RuleTrace.hit("92373179-dot-run-parts-between-dots")
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, RichTextTheme.wordWindowsPages, ctx.before == " ", ch == "." || ch == ":" || ch == ";" || ch == "," || ch == "}" || ch == ")" || ch == "]" || ch == "!" || ch == "?" || ch == "\u{BB}" || ch == "\u{203A}" {
        // (And before a closing guillemet, which the newer break table keeps with the word before its space: dx2 13c3a34e's "ville. »" ends the line at "ville." in Word's print.)
        // (A line may part at a space before a stop, colon, semicolon, comma, closing bracket, "!" or "?" (xb hin-z20395192 opens lines ":<+" and "}kjk"): the engine keeps
        // " ." together — a stop may not start a line, even after a
        // space — and Word does not. lo-0349db3a's "Word / .doc" in a
        // 116pt frame ends a line "…in Word /" in Word's print.)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, RichTextTheme.wordWindowsPages, ctx.before == ":", ch == "\\" {
        // (Word does not part a drive colon from the backslash after it: xb jpn a3f77cda's CP19d "C:\path\to\a\file"
        // carries "C:\path..." down whole, where the engine ended a line "...file C:".)
        RuleTrace.hit("colon-backslash-held")
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, RichTextTheme.wordWindowsPages, ctx.before == "\u{A1}" || ctx.before == "\u{BF}",
              let v = ch.unicodeScalars.first?.value, (v >= 0x4E00 && v <= 0x9FFF) || (v >= 0x3400 && v <= 0x4DBF) {
        // (A line may end on "¡" or "¿" when an ideograph follows: the break table reads them as
        // openers and glues them to it; Word parts after them. xb 5dc87fc7 p8 ends a line "永¿" and
        // opens the next with "永".)
        RuleTrace.hit("inverted-mark-ideograph-break")
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, RichTextTheme.wordWindowsPages, ctx.before == " ", ch != " ", let bb = ctx.beforeBefore, bb == "\u{A1}" || bb == "\u{BF}" {
        // (A line may part at the space after "¡" or "¿": the break table reads them as openers
        // and keeps what follows the space with them; Word breaks at any space. xb hin-z20395192,
        // a Kruti Dev text whose "¡" is a letter, ends a line "…'kCn l¡" and opens the next with "cuy…".)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, document.usesEastAsianLayout, ctx.before == "-", let bb = ctx.beforeBefore,
              (document.compatibilityMode ?? 12) < 15, document.characterSpacingControl?.hasPrefix("compressPunctuation") ?? false,
              let v = ch.unicodeScalars.first?.value, v > 0x20, v < 0x7F, let w = bb.unicodeScalars.first?.value, w > 0x20, w < 0x7F {
        // (Before 2013's layout, with punctuation compressed, Word
        // parts no Latin word after its hyphen either: zh-bfe04e2f
        // carries "S19-S17" down whole, where the engine ended a line
        // "…南槽航道S19-". `_fittingWordHyphens` has the same gate.)
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, RichTextTheme.wordWindowsPages, document.usesEastAsianLayout, (document.hasKana || document.eastAsiaLanguage?.hasPrefix("ja") == true), p.style.eastAsian["w:wordWrap"] != "0",
              let b = ctx.before, let bv = b.unicodeScalars.first?.value, let v = ch.unicodeScalars.first?.value,
              RichLayout._fullwidthOperatorHeld(bv, v) {
        // (Word does not part a full-width ＝ or ＋ from the ASCII "(" or digit after it: jpn-z21601833-463426's
        // "＝(" and lab eqparen; the engine breaks there as it does between ideograph and opening bracket.)
        RuleTrace.hit("fullwidth-operator-held")
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.eastAsian["w:wordWrap"] != "0", let b = ctx.before, b.isASCII, b.isLetter || b.isNumber,
              let v = ch.unicodeScalars.first?.value, v >= 0xAC00, v <= 0xD7A3 {
        // (A Latin letter or digit holds the Hangul that follows it, no space between: Word carries
        // kor-z20746312-59e77f's "26.1퍼센트였다" down whole, where the engine ended the
        // line "…신뢰도는 26.1".)
        RuleTrace.hit("hangul-held-to-latin-ctx.before-it")
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.eastAsian["w:wordWrap"] != "0",
              let b = ctx.before, let bv = b.unicodeScalars.first?.value,
              let v = ch.unicodeScalars.first?.value,
              RichLayout._hangulHeldPair(bv, v) || koreanTokenJoins.contains(offset) {
        // (Word keeps a Hangul word whole at the line end unless the paragraph's word wrap is off
        // (census of dx2 ko: 20bb671d's "학회에서", "제1저자,"); with it off it parts mid-word.)
        RuleTrace.hit("hangul-word-held-whole")
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if !theme.wordRules, theme.officeLatinBreaks, p.style.eastAsian["a:latinLnBrk"] == "0",
              let b = ctx.before, let bv = b.unicodeScalars.first?.value, let v = ch.unicodeScalars.first?.value,
              bv >= 0xAC00, bv <= 0xD7A3, v >= 0xAC00, v <= 0xD7A3 {
        // (PowerPoint breaks Korean at spaces only where the paragraph's latinLnBrk is 0:
        // 225 of 227 breaks of the decks that say so, ko-2fd3de28.)
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules || theme.officeLatinBreaks, let b = ctx.before,
              RichLayout.joinsLatin(b, ch, eastAsian: document.usesEastAsianLayout) {
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, document.usesEastAsianLayout, ch == ">", let b = ctx.before,
              let v = b.unicodeScalars.first?.value, (0x3400...0x9FFF).contains(v) || (0xF900...0xFAFF).contains(v) || v >= 0x20000,
              !RichLayout._traditionalChinese(document) {
        // (">" may not begin a line in Word's Simplified
        // Chinese list, and the engine parts it from an
        // ideograph before it: zh-3fe252ff's "…28~31行3栏>0,"
        // sends "栏" down with it in Word for Windows' print
        // (lab `lan`), ours kept "栏" and every page after p22
        // ran a line short. Not under Traditional Chinese,
        // whose list lacks it — see `_looseWordOffsets`. And
        // after an ideograph only: held to a closing bracket,
        // zh-4c884684's "…2022年）>" went down whole where
        // Word's print ends its line with it.)
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, ch == "\u{FE30}", let b = ctx.before, b != " " {
        // ("︰" may not begin a line — see `_noStart` — and the engine parts it from what it
        // follows: zh-e51c31a7's "…以為共同遵守︰" sends "守︰" down in Word's print.)
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, document.usesEastAsianLayout, (document.compatibilityMode ?? 12) < 15,
              document.characterSpacingControl?.hasPrefix("compress") == true,
              ctx.before == "-", ch.isLetter, (ch.unicodeScalars.first?.value ?? 0x3000) < 0x250,
              ctx.beforeBefore?.isLetter == true, (ctx.beforeBefore?.unicodeScalars.first?.value ?? 0x3000) < 0x250 {
        // (Latin letters only: zh-c8eb6e92's "评标-定标" parts after the
        // hyphen. Nor after a hyphen between letters, before mode 15 where
        // punctuation is compressed: labs hyc/hyd (Word for Windows,
        // zh-424775e4's package, mode 12, compressPunctuation) send
        // "China-sponsored" down whole with 25pt to spare, and
        // "langkah-langkah" too; in mode 15, or under doNotCompress,
        // it parts after the hyphen — as every other Word-win print
        // that breaks there does.)
        flush(i)
        spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, !document.usesEastAsianLayout, let b = ctx.before, RichLayout._breaksAfterHyphen(ctx.beforeBefore, b, ch) {
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    } else if theme.wordRules, !document.usesEastAsianLayout, ctx.before == "-", ch.isNumber,
              let bb = ctx.beforeBefore, bb.isLetter || bb.isNumber {
        // (Word parts a line after a hyphen before a digit —
        // "КС-" from "2).", "А-" from "5", "2024-" from "10"
        // — which the engine, keeping a number whole with
        // its sign, does not. Lab `hy3` in bug65649's
        // package, Word 16, 2026-10-15, every width that
        // ends a line between them; its page 14's "КС-2)".
        // Not under East Asian layout: zh-64044a1d's
        // "0988-228598", a cell too narrow for it, Word
        // parts after the tenth digit, not at the hyphen.)
        flush(i)
        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
        ctx.inserts.append(offset)
    }
    }
}
