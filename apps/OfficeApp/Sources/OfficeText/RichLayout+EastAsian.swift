// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "EastAsian": moved out of RichLayout.swift by test/tools/split-richlayout.py (a pure move, so that
// the parts compile side by side).

import Flutter
import FlutterSwiftBridge
import Foundation

extension RichLayout {

    /// An ASCII letter, digit or comma: what a real Latin word run has beside its last space (a "=" or "-" does not: xb jpn 5ff3d0's "n = -5〜+5）…" took "上" with the tail's room, and Word's print leaves it for the next line).
    static func _asciiWordUnit(_ u: UInt16) -> Bool {
        (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || u == 0x2C
    }

    func _fitEastAsianLines(_ p: RichParagraph, at i: Int, _ document: RichDocument, textWidth baseWidth: Double,
                                    first: TextPainter, leadWidth: Double, tabs: [Int: Double] = [:], leftTabs: Set<Int> = [],
                                    runsPast: Set<Int> = [], beyond: [Int: Double] = [:], tieShort: (first: Bool, rest: Bool) = (false, false),
                                    lineIndents: [LineIndent] = []) -> [Int: Double] {
        // (A paragraph set on both sides of a box has a room of its own on every
        // line, its pieces: `room` is the line's, from `lineIndents`.)
        var width = baseWidth
        func room(_ line: Int) -> Double { line < lineIndents.count ? max(baseWidth - lineIndents[line].left - lineIndents[line].right, 0) : baseWidth }
        // (From Word 2013's layout on, only a justified paragraph's
        // lines are fitted — set left or centred, a mark neither hangs
        // nor gives. Before it, and that is most documents written
        // elsewhere, every paragraph's are.)
        // (Outside East Asian layout only the spaces give, below.)
        // (A file that names compat mode 15 and no w:useFELayout, its defaults naming a Japanese East Asian language, is set
        // by the East Asian rules all the same: xb jpn-z19126474-754366's "…基礎として、" hangs its "、" in Word's print.)
        let latinOnly = !(document.usesEastAsianLayout || (document.autoSpacesWithoutFELayout && (document.compatibilityMode ?? 0) >= 15
            && document.eastAsiaLanguage?.hasPrefix("ja") == true && document.defaultLangXML?.containsSubstring("w:eastAsia=\"") == true
            && RichTextTheme.wordWindowsPages && p.text.unicodeScalars.contains { $0.value >= 0x3040 && $0.value <= 0x30FF || $0.value >= 0x4E00 && $0.value <= 0x9FFF }))
        // (Word for Windows lets a Latin paragraph's last "," "." ";" ")" or "}" stay on a line while its
        // origin is inside the margin, in a file that states a mode before 2013: lab `hang1`, mode 14,
        // Calibri 10pt, left; a letter never does. fas-z19537379 p5.)
        let latinStops = _latinStopsRule(latinOnly: latinOnly, document, p)
        let balancedLatinPre = RichTextTheme.wordWindowsPages && theme.wordRules && document.balancesSpaceWidth && p.cell == nil && _leftLatinSqueezeScope(document, p)
        guard theme.wordRules, !latinOnly || latinStops || balancedLatinPre || ((document.compatibilityMode ?? 12) >= 15 && p.style.alignment == .justify),
              !p.style.rightToLeft || (latinOnly && RichTextTheme.wordWindowsPages && Self._squeezesRightToLeft(p.text)), p.text.utf16.count > 2 else { return [:] }
        let legacy = (document.compatibilityMode ?? 12) < 15
        let fitted = (!latinOnly || latinStops) && (p.style.alignment == .justify || legacy)
        // (The probe is the text alone: the box before it — the first
        // line's indent — is where the first line starts from instead.)
        let lead = 0
        // (Nothing hangs out of a table's cell: a line of 24
        // ideographs and a full stop is taken at 25 ems there, where
        // the same paragraph outside a table takes it at 24 — in every
        // mode, alignment and setting of the compatibility switches
        // that sound like it, `w:doNotWrapTextWithPunct` among them.)
        let inCell = p.cell != nil
        // (Nor where the line-breaking rules are off, `w:kinsoku` 0: a
        // mark that may start a line goes to the next one rather than
        // hang — zh-b00fef0d's Normal turns them off, and Word's print
        // opens a line with "、" after "…协同更高效", where ours hung it.)
        // (A turned cell's line is the other way about: no mark gives, and
        // a closing one at its end hangs past it. The Mac's lab `tr` (Word
        // 16, zh-cec9d337's package, tbRlV, a 138.9pt row, ind 113 a side):
        // "宜蘭縣（震災，內政部）" is one column at 12pt a character, its
        // "）" 2.6pt past the row's foot; eleven ideographs make two
        // columns, ten and one. Ours squeezed "（" and "，" to fit.)
        let turned = theme.wordRules && (_cells[i]?.vertical ?? false)
        // (Nor, before 2013's layout, out of a text box: zh-2e7ef069's
        // 76pt flowchart boxes (mode 14, zh-CN, 12pt SimSun, insets 7.2)
        // send "化前期设计，" down as "设" | "计，" in Word for Windows'
        // print, 10.05pt over with its one mark, and take "工图、能评、",
        // as over, with two marks giving half each — as a cell does.)
        // (Nor, in Word for Windows, where the defaults name a Latin face for East Asian text — as its
        // marks are not compressed there, `squeezes`: zh-cd48112c's print ends no line with a mark past
        // the margin, and its "…累计扣分30-40 分（含）" sends "的，" down, stretching its one space, where
        // ours hung the "，".)
        let hangs = fitted && (!inCell || turned) && !(_inTextBox && legacy) && p.style.eastAsian["w:overflowPunct"] != "0" && p.style.eastAsian["w:kinsoku"] != "0"
            && !(RichTextTheme.wordWindowsPages && document.eastAsianDefaultFaceIsLatin)
            && !(RichTextTheme.wordWindowsPages && theme.wordRules && (document.compatibilityMode ?? 12) == 14 && document.markSqueezeEm == 0
                 && document.characterSpacingControl == "compressPunctuation")
        // (Nor at compat 14 under compressPunctuation without a Chinese or Japanese language: lab comma-hang7 v6/v8, a
        // line-end mark opens the next line, none hangs.)
        // (Nor where the defaults name a Latin face for East Asian text, in
        // Word for Windows: `RichDocument.eastAsianDefaultFaceIsLatin`.)
        let squeezes = fitted && !turned && (document.characterSpacingControl?.hasPrefix("compressPunctuation") ?? false)
            && !(RichTextTheme.wordWindowsPages && document.eastAsianDefaultFaceIsLatin)
            && !(RichTextTheme.wordWindowsPages && theme.wordRules && (document.compatibilityMode ?? 12) == 14 && document.markSqueezeEm == 0)
        // (Compat 14, compressPunctuation, but no Chinese or Japanese eastAsia language, or ko-KR: lab comma-hang7
        // v6/v8 measure every mark's advance at the full 12.0 of 12 pt and 16.0 of 16 pt, so Word squeezes none.)
        // (From 2013's layout on a justified line's spaces give a quarter
        // of themselves for a word that is over: Cambria at 14pt takes
        // it 0.5pt over with one space and not 1.0, 1.5 with two and not
        // 2.0, 3.0 with four and not 3.5, 6.0 with eight and not 6.5 —
        // lab `js`, `body50.py`, 2026-10-14; zh-4b8e0abc's Indonesian
        // lines take a word ours left for the next.)
        // (Before it, a page field's result with no ideograph in it gives
        // them so set as it is, since it cannot break at its own spaces:
        // zh-c4f2be3b's eaVert page number " - 10 -" (mode 14, right-
        // aligned, SimSun 14pt, 49pt in a 47.3pt box) is one line in Word
        // for Windows' print, its two inner spaces 6.1 for 7. Any legacy
        // paragraph without ideographs giving them costs bug57031 and
        // zh-d62da4dd lines.)
        let units = Array(p.text.utf16)
        // (A left-aligned paragraph under the balance gives its Latin word spaces too, down to half, when that takes one more word, below compat 15 (lab sqz2, SimSun: 16 words a line at none, 12 and 14, 15 at compat 15, same in en, ja and zh). PROVISIONAL scope: left-aligned, useFELayout, zh; centred zh-90e0cea8, Korean Malgun ecc32adb and plain Latin gv-f711169b, fra-g188 must NOT squeeze:
        // oxsdk-1c09b12993's notes, no jc, SimSun 10.5, spaces 5.28 on lines that end short and 2.52-4.7 on lines that end on the margin.)
        let balancedLatinSqueeze = legacy && RichTextTheme.wordWindowsPages && theme.wordRules && document.balancesSpaceWidth && !inCell && _leftLatinSqueezeScope(document, p)
        let squeezesSpaces = !legacy && p.style.alignment == .justify
            || legacy && fitted && units.contains(0x2060)
                && !units.contains(where: { $0 >= 0x2E80 })
            || legacy && fitted && p.style.alignment == .justify && document.usesEastAsianLayout && !inCell && RichTextTheme.wordWindowsPages
                && document.characterSpacingControl == "compressPunctuation" && !units.contains(where: { $0 >= 0x2E80 })
                && document.eastAsiaLanguage != nil && !["zh", "ja", "ko"].contains(where: { document.eastAsiaLanguage?.hasPrefix($0) == true })
            || balancedLatinSqueeze
        // (A page number set apart by dashes in a text box, its field result
        // unmarked, gives them too, up to two fifths: zh-4e5fe46f's "— 10 —", 14pt
        // SimSun in 51.1pt, is one line in Word's print, the space after its
        // first dash 3.7 for 7, about a third of the line's 10.5 of spaces; zh-e8bf8b42's
        // "— 3 —" needing half of them keeps its line broken, as in Word's print.)
        let pageBox = legacy && fitted && _inTextBox && units.contains(where: { $0 >= 0x30 && $0 <= 0x39 })
            && units.allSatisfy { $0 == 0x20 || $0 == 0x2014 || $0 == 0x2D || ($0 >= 0x30 && $0 <= 0x39) }
        // (Where nothing else is compressed, `w:topLinePunct` still lets a
        // line's opening mark give: see `leadOpeners` below.)
        // (A Japanese document, by its kana or its language: no 、 or 。 with text after it hangs at c15 with a grid, where the
        // zh-CN rule above holds it too; labs c67lab c15 16 pt, Word keeps a mid-line 、 inside the margin.)
        let noHangJa = RichTextTheme.wordWindowsPages && theme.wordRules && (document.compatibilityMode ?? 12) >= 15 && document.lineGridPitch != nil
            && (document.hasKana || document.eastAsiaLanguage?.hasPrefix("ja") == true) && units.contains(where: { $0 >= 0x3040 && $0 <= 0x30FF })
        let squeezesPauseRule = RichTextTheme.wordWindowsPages && theme.wordRules && (document.compatibilityMode ?? 12) >= 15 && document.lineGridPitch != nil && document.marksSitLeft && units.contains(where: { $0 >= 0x3040 && $0 <= 0x30FF })
        let topLinePunct = fitted && !turned && p.style.eastAsian["w:topLinePunct"] == "1"
        let topOnly = topLinePunct && !squeezes && units.contains(where: { Self._openingUnits.contains($0) })
        // (Marks to hang or squeeze, or a letter or digit an automatic
        // space may stand beside.)
        let marked = topOnly || (hangs || squeezes) && units.contains(where: { Self._hangingUnits.contains($0) || Self._openingUnits.contains($0) })
            || squeezes && (units.contains(0xB7) || units.contains(0x30FB))   // (a middle dot set an em gives too: `wideDot`)
        // (Or a closing mark before an opening one, which a line may part
        // and so end on the closing one whole — `parted` below — where
        // marks are not compressed: zh-147bdae0's cell paragraph "…管理系
        // 統」（紙本申報）…", set left, with nothing else to fit for.)
        let partable = RichTextTheme.wordWindowsPages && !latinOnly && !turned
            && zip(units, units.dropFirst()).contains { Self._closingUnits.contains($0.0) && Self._openingUnits.contains($0.1)
                && (!squeezes || !Self._pauseMarks.contains($0.0)) }
        let hangulParen = RichTextTheme.wordWindowsPages && hangs && !units.contains(where: { $0 < 0x250 && ($0 >= 0xC0 && $0 != 0xD7 && $0 != 0xF7 || $0 >= 0x41 && $0 < 0xA0 || ($0 >= 0x30 && $0 <= 0x39)) }) && zip(units, units.dropFirst()).contains { $0.1 == 0x29 && $0.0 >= 0xAC00 && $0.0 <= 0xD7A3 }
        // (A Korean line's final "." or "," after a Hangul syllable stays while its origin is inside the margin, in the
        // body below 2013's layout: lab ko-stop, Gulim 12pt left, all-Hangul line, kept from 316.0 against a natural
        // 320.1 at compat 14; at compat 15 and in a cell it needs the whole 320.0, as before.)
        let hangulStop = RichTextTheme.wordWindowsPages && legacy && hangs
            && zip(units, units.dropFirst()).contains { ($0.1 == 0x2E || $0.1 == 0x2C) && $0.0 >= 0xAC00 && $0.0 <= 0xD7A3 }
        // (Under compressPunctuation a line may end on an opening mark: see `squeezeOpen` below.)
        let openerLine = squeezes && (document.hasKana || document.eastAsiaLanguage?.hasPrefix("ja") == true) && RichTextTheme.wordWindowsPages && (document.compatibilityMode ?? 12) >= 15 && p.style.eastAsian["w:kinsoku"] != "0"
            && units.contains(where: { Self._openingUnits.contains($0) })
        guard marked || partable || hangulParen || hangulStop || openerLine || units.contains(where: { $0 < 0x250 && ($0 >= 0x41 || ($0 >= 0x30 && $0 <= 0x39)) })
                || (squeezesSpaces && units.contains(0x20)),
              first.computeLineMetrics().count > 1 else { return [:] }
        // What each character's automatic space after it is.
        var gaps: [Int: Double] = [:]
        let (span, inline, inserts) = _span(for: p, at: i, document, textWidth: width, lead: 0, adjust: tabs, autoSpaces: { gaps[$0] = $1 })
        // (Marks to hang, or full stops and commas an older file's line may
        // end on past the margin: `RichDocument.hangsLatinStops`.)
        let stops = (document.hangsLatinStops && RichTextTheme.wordWindowsPages && legacy && hangs
            && units.contains(where: { $0 == 0x2E || $0 == 0x2C }))
            || latinStops && units.contains(where: { Self._latinStopUnits.contains($0) })
            || hangulParen || hangulStop
        guard marked || stops || partable || openerLine || !gaps.isEmpty || ((squeezesSpaces || pageBox) && units.contains(0x20)) else { return [:] }
        let map = _OffsetMap(lead: 0, inserts: inserts)
        // Where a zero-width space lets the line break (a word joiner,
        // the other thing `_span` puts in, does the opposite).
        // (Under `w:kinsoku` off, too, where `_span` lets a closing mark
        // start a line or an opening one end it: the mark is a piece of
        // its own, judged alone — zh-9e08ed28's cell line "，以落實成效。"
        // is 0.5 over and taken in Word, the "，" having gone down from
        // "目" before it; glued as "目，" the line ran a piece behind and
        // the "。" went down alone.)
        let kinsokuOff = p.style.eastAsian["w:kinsoku"] == "0"
        // (Under compressPunctuation, kinsoku on, Word for Windows may end a line on an opening mark squeezed: `_span`.)
        let squeezeOpen = !kinsokuOff && squeezes && (document.hasKana || document.eastAsiaLanguage?.hasPrefix("ja") == true) && RichTextTheme.wordWindowsPages && theme.wordRules && (document.compatibilityMode ?? 12) >= 15
        // (Or where the mark's run has no East Asian line rules.)
        var runOf: [Int] = []
        for (k, r) in p.runs.enumerated() { runOf.append(contentsOf: repeatElement(k, count: r.length)) }
        let wordRules = theme.wordRules
        let lineStyle = _named(p, document)
        let runRulesOff: (Int) -> Bool = { o in
            guard wordRules, o >= 0, o < runOf.count else { return false }
            return !Self._eastAsianLineRules(p.runs[runOf[o]].style, document, named: lineStyle)
        }
        // (Nor a mark in a face Word compresses nothing in:
        // `RichDocument.uncompressedFaces`. zh-57f1de0d's 》 and ：
        // stay whole in its embedded 方正仿宋_GBK where ours gave 2.65 each
        // and took "化"; the gaps beside its digits still give. Word for
        // Mac too: its print breaks the same lines, 78.9 -> 94.4 there.)
        let uncompressed: (Int) -> Bool = { o in
            guard !document.uncompressedFaces.isEmpty, o >= 0, o < runOf.count else { return false }
            let style = p.runs[runOf[o]].style
            guard let face = style.eastAsiaFontFamily ?? lineStyle?.char.eastAsiaFontFamily ?? self._normalChar(document)?.eastAsiaFontFamily else { return false }
            return document.uncompressedFaces.contains(face)
        }
        let runLanguageNone: (Int) -> Bool = { o in
            guard wordRules, o >= 0, o < runOf.count else { return false }
            return Self._eastAsianLanguageNone(p.runs[runOf[o]].style, named: lineStyle) || uncompressed(o)
        }
        let percentStarts = _percentStarts(document)
        // (Nor inside Han text `_span` joins: `_hanJoins`.)
        let hanJoins = wordRules ? Self._hanJoins(p, document, index: i, fitChars: _hanFitChars(p, named: _named(p, document), textWidth: width)) : []
        // (And Thai `_span` keeps together, one piece as the engine has it:
        // set apart, each letter was judged a word of its own — Word for
        // Mac's p17 heading of zh-6a4fc013, "…ใช้วิธีคำนวณ…ใช่หรือไม่?", is
        // taken whole with its "：" squeezed and its "?" hung, where ours
        // held back the "ม" that started near the margin.)
        let thaiJoins = _thaiJoins(p, document, named: _named(p, document), textWidth: width, lead: 0)
        func thaiLetter(_ u: UInt16) -> Bool { u >= 0x0E01 && u <= 0x0E5B }
        func eastAsianRunAt(_ o: Int) -> Bool {
            guard o >= 0, o < runOf.count else { return false }
            let style = p.runs[runOf[o]].style
            let face = theme.faceResolver?(style.fontFamily ?? lineStyle?.char.fontFamily ?? theme.fontFamily, false)
            let high = (style.hAnsiFontFamily ?? lineStyle?.char.hAnsiFontFamily).flatMap { theme.faceResolver?($0, false) }
            let hint = style.fontHint ?? lineStyle?.char.fontHint
            return hint == "eastAsia" || (face?.isEastAsian ?? false) && (hint != "default" || (high?.isEastAsian ?? true))
        }
        let hangulJoins = Self._hangulJoins(p, inserts: inserts, units: units, wordRules: wordRules)
        let ellipsisStarts = Self._ellipsisMayStart(document)
        let breakBefore = Set(inserts.filter { o in
            guard o > 0, o < units.count, !hanJoins.contains(o), let a = Unicode.Scalar(units[o - 1]), let b = Unicode.Scalar(units[o]) else { return false }
            // (But not an opening mark at a line's end, either way: Word
            // carries "（" over with what it opens — zh-c5b5087b, its
            // defaults' East Asian language en-US and kinsoku off, has
            // "…负责承储" / "（以下简称…" where ours ended the line on it.)
            if wordRules, b.value == 0x3001, o < runOf.count, Self._dunhaoMayStart(p.runs[runOf[o]].style, document, named: lineStyle) { return true }
            if kinsokuOff || runRulesOff(o), Self._closingMarks.contains(Character(b)) || Self._latinCloser(Character(a), Character(b)) { return true }
            // (… and under `w:kinsoku` 0: zh-b00fef0d's "…调度困难" opens its next line with "”".)
            if runRulesOff(o) || (kinsokuOff && RichTextTheme.wordWindowsPages && eastAsianRunAt(o)), Self._closingQuote(Character(b)) { return true }
            // (… and an opening one end it, under `w:kinsoku` 0 in text of
            // an East Asian language — zh-72da925e's "…（下稱「": see `_span`.)
            if kinsokuOff, !runRulesOff(o - 1), Self._openingMarks.contains(Character(a)) || Self._latinOpener(Character(a), Character(b)) { return true }
            if squeezeOpen, Self._openingMarks.contains(Character(a)), b.value != 0x20 { return true }
            if kinsokuOff, RichTextTheme.wordWindowsPages, !runRulesOff(o - 1), a.value == 0x201C || a.value == 0x2018, eastAsianRunAt(o - 1) { return true }
            // (In a line too narrow for one character, at every one: see `_span`.)
            if wordRules, width < _px(p.runs.first?.style.fontSize ?? lineStyle?.char.fontSize ?? theme.fontSize) { return true }
            // (Not between an em dash and the digits after it where a closing mark stands before the dash: see `_span`.)
            if wordRules, a.value == 0x2014, b.value >= 0x30, b.value <= 0x39, o > 1, Self._closingUnits.contains(units[o - 2]) { return false }
            return Self._breaksBetween(Character(a), Character(b), percentStarts: percentStarts,
                                       timesEastAsian: !Self._eastAsianSigns.contains(units[o - 1]) || _setEastAsian(p, document, at: o - 1),
                                       shapesPart: (document.compatibilityMode ?? 12) >= 15 || RichTextTheme.wordWindowsPages,
                                       latinQuotes: wordRules && !_setEastAsian(p, document, at: o - 1) && !_setEastAsian(p, document, at: o))
                || (latinOnly && Self._breaksAfterHyphen(o > 1 ? Unicode.Scalar(units[o - 2]).map { Character($0) } : nil, Character(a), Character(b), letters: true))
        }).union(_looseWordOffsets(p, document, textWidth: width, named: _named(p, document),
                                   pitch: _offGrid(i, document) ? nil : _grid(i, document).pitch))
          .union(_fittingWordHyphens(p, document, textWidth: width, named: _named(p, document),
                                     pitch: _offGrid(i, document) ? nil : _grid(i, document).pitch))
          // (And automatic hyphenation's points, where the engine will part a
          // word: zh-147bdae0's cell paragraph ends its first line "（Peter
          // Bell-", in Word's print and ours, but was weighed here with
          // "Bellwood）" whole, and every line after it was judged on breaks
          // the page never had — "…禮物〉" was taken 3.9pt over.)
          .union(wordRules ? (_hyphenPoints[i] ?? []) : [])
        let probe = TextPainter(text: span, textAlign: .left, textDirection: .ltr)
        if !inline.isEmpty { probe.setPlaceholderDimensions(inline.map { $0.dimensions }) }
        probe.layout(minWidth: 0, maxWidth: 1)
        defer { probe.dispose() }
        // The size (pixels) of the run at each offset: a mark's em.
        var ems: [Double] = []
        ems.reserveCapacity(units.count)
        let named = _named(p, document)
        var closing: [Bool] = []
        // Whether a curly quote at each offset is the full-width one
        // (East Asian text's, see `_span`): a mark like a bracket.
        var wideQuotes: [Bool] = []
        var eastAsianRuns: [Bool] = []   // each offset's run set East Asian (`eastAsianAt`)
        for run in p.runs {
            let em = (run.style.fontSize ?? named?.char.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
            ems.append(contentsOf: repeatElement(em, count: run.length))
            closing.append(contentsOf: repeatElement(_closesUpMarks(run.style, named, document), count: run.length))
            let face = theme.faceResolver?(run.style.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, false)
            let hint = run.style.fontHint ?? named?.char.fontHint
            let high = (run.style.hAnsiFontFamily ?? named?.char.hAnsiFontFamily).flatMap { theme.faceResolver?($0, false) }
            let hinted = hint == "eastAsia" || (face?.isEastAsian ?? false) && (hint != "default" || (high?.isEastAsian ?? true))
            // (Not a face with quotes of its own width: `_span`.)
            let ownQuotes = theme.faceResolver?(run.style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                                ?? run.style.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.otherAdvances?[0x201C] != nil
            wideQuotes.append(contentsOf: repeatElement(hinted && !ownQuotes, count: run.length))
            eastAsianRuns.append(contentsOf: repeatElement(hinted, count: run.length))
        }
        guard ems.count == units.count else { return [:] }
        // (Whether the character at an offset is set as East Asian text: an
        // ideograph, or a symbol its run, hinted East Asian, sets in its East
        // Asian face — zh-dc25c47e's "□", "※".)
        func eastAsianAt(_ k: Int) -> Bool {
            units[k] >= 0x2E80 || eastAsianRuns[k] && units[k] >= 0x2100 && Self.isEastAsian(Character(Unicode.Scalar(units[k]) ?? " "), hinted: true)
        }
        func wideQuote(_ k: Int) -> Bool { wideQuotes[k] && (units[k] == 0x201C || units[k] == 0x201D || units[k] == 0x2018 || units[k] == 0x2019) }
        // (The spacing a full-width quote is set wider by: its run's, twice
        // where the widths are balanced — the quote is set in the Latin
        // face, so its box does not hold it as an ideograph's does.)
        func quoteSpacing(_ k: Int) -> Double {
            guard theme.wordRules, k < runOf.count else { return 0 }
            let sp = (p.runs[runOf[k]].style.letterSpacing ?? lineStyle?.char.letterSpacing ?? _normalChar(document)?.letterSpacing ?? 0)
            return max(0, sp) * theme.pixelsPerPoint * scale * (document.balancesSpaceWidth ? 2 : 1)
        }
        // (A no-break space of the text's own is a character like any
        // other: it is not what a line may end with for nothing.)
        func isSpace(_ u: UInt16) -> Bool { u == 0x20 || u == 0x3000 || u == 0x09 }
        func closesUp(_ k: Int) -> Bool {
            guard closing[k], k + 1 < units.count, let a = Unicode.Scalar(units[k]), let b = Unicode.Scalar(units[k + 1]) else { return false }
            // (JIS X 4051's pair table: a closing mark before a middle dot closes up to its half, as before a full
            // stop. Lab `jis4051`: Word keeps "…」・国" as far as "…」。国", to 9.75 pt over; ours refused from 6.5.)
            return Self.closesUp(Character(a), Character(b), centred: document.marksCentred)
                || (noHangJa && units[k + 1] == 0x30FB && Self._closingBracketMarks.contains(Character(a)))
                || (Self._closingMarks.contains(Character(a)) && (units[k + 1] == 0x201C || units[k + 1] == 0x2018) && wideQuote(k + 1))
                || ((units[k] == 0x201D || units[k] == 0x2019) && wideQuote(k)
                    && (Self._closingMarks.contains(Character(b)) || Self._openingMarks.contains(Character(b))
                        || ((units[k + 1] == 0x201C || units[k + 1] == 0x2018) && wideQuote(k + 1))))
        }
        // The probe's lines are the engine's clusters (at no width it
        // breaks even inside a word): each with its width, and its
        // trailing spaces' apart, which the engine leaves out of a line's
        // width and of its fit.
        struct Piece { var a: Int; var b: Int; var last: Int; var w: Double; var trail: Double; var hard: Bool }
        var pieces: [Piece] = []
        var start = 0           // painter offset
        let total = units.count + inserts.count
        // (Thai measured on the text laid out as one line: the probe at no
        // width parts "จั" after the consonant, whose box then measures
        // nothing — zh-6a4fc013's "คำถามที่ 9 ：การจัดสรร…" came to 77pt
        // under its width, so the line was never squeezed, where Word's
        // print squeezes it to hold "เป็นอย่างไร?". Each piece there is the
        // advance from its start to the next piece's.)
        let shownUnits = Array(span.toPlainText(includeSemanticsLabels: false, includePlaceholders: true).utf16)
        // (The probe parts a cluster it cannot set on one line, so a script it
        // cannot measure per character reads as zero: any step the probe sums
        // to nothing takes the width from one unbroken line instead. That is
        // built on first need, so Latin and ideographs never pay for it.)
        var flat: TextPainter?
        let flatUsable = wordRules && shownUnits.count == total
        defer { flat?.dispose() }
        func flatX(_ o: Int) -> Double {
            if flat == nil {
                let t = TextPainter(text: span, textAlign: .left, textDirection: .ltr)
                if !inline.isEmpty { t.setPlaceholderDimensions(inline.map { $0.dimensions }) }
                t.layout(minWidth: 0, maxWidth: 10_000_000)
                flat = t
            }
            guard let flat else { return 0 }
            if o >= total { return flat.width }
            return flat.getOffsetForCaret(TextPosition(offset: o), Rect.zero).dx
        }
        // (An Indic range measured on the one-line layout, between cluster boundaries: a boundary inside a cluster reads as the
        // cluster's end, so the piece that opens a cluster takes its whole width and the pieces after it nothing.)
        func indicBound(_ k: Int) -> Int {
            var k = k
            while k < units.count, let u = Unicode.Scalar(UInt32(units[k])), k > 0 {
                let cont = u.properties.generalCategory == .nonspacingMark || u.properties.generalCategory == .spacingMark
                    || u.value == 0x200C || u.value == 0x200D
                    || (Unicode.Scalar(UInt32(units[k - 1])).map { $0.properties.canonicalCombiningClass.rawValue == 9 } ?? false)
                if !cont { break }
                k += 1
            }
            return k
        }
        func indicWidth(_ from: Int, _ to: Int) -> Double {
            let a = indicBound(from), b = indicBound(to)
            guard b > a else { return 0 }
            return max(0, flatX(b >= units.count ? total : map.painter(b)) - flatX(map.painter(a)))
        }
        // (Walked by the lines' boundaries, and measured by the boxes
        // of what is between them: the engine's count of lines is not
        // the count of those where a space is set wider than it is.)
        func boxes(_ from: Int, _ to: Int) -> Double {
            guard to > from else { return 0 }
            var w = 0.0
            // (At no width the probe may part a cluster over several lines — "मैं" is a consonant on one and its signs on the next — and
            // reports the whole cluster's width for each part, so the boxes summed read twice the cluster: "मैं" 8.45 pt where the engine
            // sets it 4.225, "समझता" 24.92 against 20.05. An Indic range is therefore measured by the boxes of its cluster-opening
            // characters only, each once.)
            // (Thai the same: a mark's box at no width carries its consonant's whole width, so a word summed 5-20% over the engine's line
            // — 28fa7f69's FITW: 286 against 232 pt.)
            // (Myanmar too: 80bde9af's FITW read words 2x the engine's, 323 against 145 pt.)
            func clustered(_ u: UInt16) -> Bool { (u >= 0x0900 && u <= 0x0DFF) || (u >= 0x0E01 && u <= 0x0E5B) || (u >= 0x1000 && u <= 0x109F) }
            if flatUsable, units[from ..< to].contains(where: clustered)
                || (flatUsable && from > 0 && clustered(units[from - 1]) && units[from ..< to].allSatisfy({ $0 == 0x20 })) {
                return indicWidth(from, to)
            }
            for box in probe.getBoxesForSelection(TextSelection(baseOffset: map.painter(from), extentOffset: map.painter(to - 1) + 1)) {
                w += box.right - box.left
            }
            return w
        }
        func wideDot(_ k: Int) -> Bool { (units[k] == 0xB7 || units[k] == 0x30FB && !squeezesPauseRule) && k < ems.count && boxes(k, k + 1) >= ems[k] * 0.9 }
        // (What `_span` put in before a character and the engine set
        // on a line of its own: a word joiner as wide as an opening
        // quote's blank. Its width goes with what follows it.)
        var pending = 0.0
        func endsOpening(_ g: Piece?) -> Bool {
            guard let g, g.last > g.a, g.last < g.b else { return false }
            return Self._openingUnits.contains(units[g.last - 1])
        }
        while start < total {
            let r = probe.getLineBoundary(TextPosition(offset: start))
            let end = min(total, max(start + 1, r.end))
            let a = min(units.count, map.paragraph(start)), b = min(units.count, max(a, map.paragraph(end)))   // paragraph offsets
            let from = start
            start = end
            guard b > a else {
                var w = 0.0
                for box in probe.getBoxesForSelection(TextSelection(baseOffset: from, extentOffset: end)) { w += box.right - box.left }
                // (One after a no-break space is that space's: the em a
                // no-break space after an ideograph takes rides on it.
                // zh-c6ab068c's "…予以公开。" + U+00A0 ends its paragraph,
                // and the joiner's 7pt, given to nothing after it, was
                // lost — the stretch taken whole here and parted by the
                // engine, "开。" a line down where Word's print squeezes
                // the line's marks for it.)
                // (And a hyphen drawn where automatic hyphenation ends a line
                // is the end of that line, not the start of the next: "（Peter
                // Bell-" above.)
                if a > 0, units[a - 1] == 0xA0 || (wordRules && _hyphenShown[i]?.contains(a) == true),
                   !pieces.isEmpty, pieces[pieces.count - 1].b == a { pieces[pieces.count - 1].w += w }
                else { pending += w }
                continue
            }
            var last = b
            while last > a, isSpace(units[last - 1]) { last -= 1 }
            let trail = boxes(last, b)
            // (From the line's own start: one may sit on this line too.)
            var lineWidth = pending
            if last > a {
                var probed = 0.0
                for box in probe.getBoxesForSelection(TextSelection(baseOffset: from, extentOffset: map.painter(last - 1) + 1)) {
                    probed += box.right - box.left
                }
                // (At no width the probe parts an Indic cluster over lines and gives each part the whole cluster's box, so a piece
                // reads more than the engine sets it — "लेन-" 11.94 pt against 7.12 — and a line is called full a word early: the
                // piece is measured on the one-line layout, between cluster boundaries, as `boxes` does.)
                if flatUsable, units[a ..< last].contains(where: { $0 >= 0x0900 && $0 <= 0x0DFF }) {
                    probed = indicWidth(a, last)
                } else if flatUsable, Self._probeCannotMeasure(probed, units[a ..< last]) {
                    probed = max(0, flatX(map.painter(last - 1) + 1) - flatX(from))
                }
                lineWidth += probed
            }
            pending = 0
            let hard = units[b - 1] == 0x0A || units[b - 1] == 0x2028 || units[b - 1] == 0x0B || end >= total
            // Clusters the engine will not part are one stretch: a space
            // stays with what it follows, and so does whatever may not
            // start a line or follows what may not end one — unless a
            // zero-width space stands between them.
            // (And an opening mark with spaces after it from what follows
            // them: a line ends with no "（" for its spaces' sake. Word
            // keeps zh-69bbcc3c's "一般项（   ）" whole at a line's end,
            // its five marks giving 4.9pt each and "）" hanging; parted,
            // ours ended the line "（" and set "）" a line down.)
            let opens = endsOpening(pieces.last)
            // (And a closing mark with what its spaces follow, as `_span`
            // keeps it: zh-f47b8a74's "至" and 19 underlined spaces go down
            // with the "，账号" after them in Word's print.)
            let closesAfterSpaces = wordRules && document.usesEastAsianLayout && !kinsokuOff && !runRulesOff(a) && a < units.count
                && Self._closingMarks.contains(Character(Unicode.Scalar(units[a])!)) && pieces.last.map { $0.last < $0.b && $0.last > $0.a && units[$0.b - 1] == 0x20 } == true
            if var g = pieces.last, !g.hard, g.b == a, g.b > g.a, !breakBefore.contains(a),
               last == a || (g.last == g.b && Self._glued(units[g.b - 1], units[a], strict: Self._strictKinsoku(document)) && !(units[a] == 0x2026 && ellipsisStarts) && !(squeezesPauseRule && (units[a] == 0x3001 || units[a] == 0x3002) && !Self._closingUnits.contains(units[g.b - 1]))) || (opens && last > a) || (closesAfterSpaces && last > a)
                || (wordRules && g.b >= 2 && units[g.b - 1] == 0x2014 && units[a] >= 0x30 && units[a] <= 0x39 && Self._closingUnits.contains(units[g.b - 2]))
                || (RichTextTheme.wordWindowsPages && p.style.rightToLeft && g.last == g.b && a > 0 && units[a - 1] >= 0x0620 && units[a - 1] <= 0x06FF && units[a] >= 0x0620 && units[a] <= 0x06FF)
                || hanJoins.contains(a) || hangulJoins.contains(a) || (thaiJoins.contains(a) && a > 0 && thaiLetter(units[a - 1]) && thaiLetter(units[a])) {
                if (opens || closesAfterSpaces) && last > a { g.w += g.trail; g.trail = 0 }
                g.w += lineWidth
                g.b = b
                if last > a { g.last = last }
                g.trail += trail
                g.hard = hard
                pieces[pieces.count - 1] = g
            } else {
                pieces.append(Piece(a: a, b: b, last: last, w: lineWidth, trail: trail, hard: hard))
            }
        }
        var loggedParagraph = false
        var adjust: [Int: Double] = [:]
        // (A stretch no line of the cell can hold gives its closing marks'
        // halves before the engine parts it: zh-007ca091's unit cells,
        // "套（台）" in 23.6pt, are "套" / "（" / "台）" in Word's print — the
        // "）" set half an em narrower — where ours parted "台" from "）"
        // too, and every such row stood a line taller.)
        if theme.wordRules, inCell {
            for piece in pieces where piece.w > width + _px(0.01) {
                for k in piece.a ..< piece.last where Self._closingUnits.contains(units[k]) && units[k] >= 0x3000 && k < ems.count {
                    adjust[k, default: 0] -= ems[k] / 2
                }
            }
        }
        var x = leadWidth
        var lineNumber = 0
        width = room(0)
        // (Under `w:topLinePunct` the opening mark a line starts with gives
        // its blank half as any mark does, whatever characterSpacingControl
        // says, and gives it from its left: zh-1cfb652b's "《城市建筑垃圾管理
        // 规定》…在运送过程" (doNotCompress, 仿宋_GB2312 16pt, justified)
        // starts 8.5pt left of the margin in both of Word's prints and takes
        // "程"; its "（一）包秩序…乱刻画、" first line the same, where the
        // short "（一） 高空抛物；" keeps its indent. Where the settings
        // compress, the first line's is given before the fit,
        // `_topLineSqueeze`.)
        let firstGiven = _topLineSqueeze(p, document) > 0
        var leadOpeners: [Int: Int] = [:]   // a line's giving opener, and where its line ends
        // (A circled number ①–⑳ is set an em wide, an ideograph at the line's end: zh-30d86fcf's "…申请条件。③" is
        // taken 0.7 over in Word's print, as the ideographs beside it are.)
        func circled(_ u: UInt16) -> Bool { RichTextTheme.wordWindowsPages && theme.wordRules && u >= 0x2460 && u <= 0x24FF }
        var closingOpeners = Set<Int>()   // a closing mark that opens its line (Word keeps it whole when it is the only mark to give)
        var marks: [Int] = []   // this line's marks that still have their whole em
        var spaces: [Int] = []  // this line's characters with an automatic space after them
        var opening = true      // nothing on the line yet
        var lineRaised = false  // a raised number the line opens with (see below)
        var lineTabbed = false  // a tab stands on the line (see `afterTabSpace`)
        var onFirstLine = true  // the paragraph's first line, which its first-line indent sets
        var lineWide = 0        // this line's characters, and whether it has spaces among them
        var lineFrom = 0        // where this line starts
        var lineEms = 0.0       // … and their ems, summed
        var lineLatin = false   // … and whether any is not East Asian (see `edge`)
        var lineLetters = false // … and whether any is a Latin letter (see `gridCapped`)
        let onCharacterGrid = (_grid(i, document).chars ?? 0) != 0
        let gridAdd = p.style.eastAsian["w:snapToGrid"] == "0" ? 0 : _px(_grid(i, document).chars ?? 0)
        // (Not a character whose run is off the grid, as `_span` sets it:
        // zh-c15af02e's runs say `w:snapToGrid` 0 on a grid of 1pt, their
        // 16pt ideographs 16 apart, and Word's print takes "…已核發" 13.58pt
        // over with four marks giving — weighed at 17 a character, ours
        // left it.)
        let runsOffGrid: [Bool] = p.runs.map { run in
            run.style.keptXML?.containsSubstring("<w:snapToGrid") ?? false
                ? run.style.keptXML?.containsSubstring("<w:snapToGrid w:val=\"0\"") ?? false
                : theme.wordRules && (lineStyle?.char.keptXML?.containsSubstring("<w:snapToGrid w:val=\"0\"") ?? false)
        }
        var lineOther = false
        var lineSpaced = false  // … or ends, so far, with one
        var lineBlank = false   // a space character (U+0020) on the line so far
        var wordSpaces: [(k: Int, w: Double)] = []   // this line's space characters, and their widths
        var spaceBaseX = 0.0   // x where the text before the line's last space ends (where that word starts)
        var breaks: [(end: Int, opener: Range<Int>, over: Double)] = []   // where a line ended because what followed was over
        // (A line's word spaces, measured: lab `wsf` (Word for Windows, 14pt, mode 15, 24 ideographs
        // and the next one taken as the line's width steps down, spaces 4 or 8, commas 0, 1 or 3,
        // balance on and off, spaces in 標楷體 or Times, between ideographs or inside Latin words).
        // One rule gives its sixty rows, 8 of them a half point out (the step): what the line
        // must give, as a share of G, is no more than what it would stretch by, as a share of E —
        //   G = half of each mark + a quarter of each word space (0.23 with East Asian text on either side)
        //   E = a sixty-fourth of each gap's em + each automatic space + 0.47 of each word space
        // and under the balance a space with East Asian text on both sides gives nothing, and
        // weighs nothing in E either where it is set in a Latin face. Underlined or not is the same.)
        func flankedSpace(_ k: Int) -> Bool {
            var l = k - 1, r = k + 1
            while l >= 0, isSpace(units[l]) { l -= 1 }
            while r < units.count, isSpace(units[r]) { r += 1 }
            return l >= 0 && r < units.count && units[l] >= 0x2E80 && units[r] >= 0x2E80
        }
        func spaceGives(_ k: Int) -> Bool { !(document.balancesSpaceWidth && flankedSpace(k)) }
        func spaceGiveShare(_ k: Int) -> Double {
            var l = k - 1, r = k + 1
            while l >= 0, isSpace(units[l]) { l -= 1 }
            while r < units.count, isSpace(units[r]) { r += 1 }
            return (l >= 0 && units[l] >= 0x2E80) || (r < units.count && units[r] >= 0x2E80) ? 0.23 : 0.25
        }
        func spaceWeighs(_ k: Int) -> Bool { !(document.balancesSpaceWidth && flankedSpace(k) && !eastAsianRuns[k]) }
        // (What the line would stretch by at its gaps: a sixty-fourth of an em at each.)
        func gapStretch() -> Double {
            guard lineWide > 0 else { return 0 }
            return lineEms * Double(lineWide - 1) / Double(lineWide) / 64
        }
        // (The pieces of the word a piece is in: from its first piece to the one that ends it, none before the line's first.)
        func indicWordPieces(_ index: Int) -> (start: Int, end: Int) {
            var st = index
            while st > 0, pieces[st - 1].b == pieces[st].a, pieces[st - 1].last == pieces[st - 1].b, pieces[st - 1].trail == 0, !pieces[st - 1].hard, pieces[st - 1].a >= lineFrom { st -= 1 }
            var en = index
            while en + 1 < pieces.count, pieces[en].trail == 0, pieces[en].last == pieces[en].b, !pieces[en].hard, pieces[en + 1].a == pieces[en].b { en += 1 }
            return (st, en)
        }
        var pastFrom: (x: Double, tab: Int)? = nil   // where a tab to a right stop at the margin starts, the piece before ending with it
        var wordRest = 0   // pieces of an Arabic word a squeeze took whole, already on the line
        for (pieceIndex, piece) in pieces.enumerated() {
            if wordRest > 0 { wordRest -= 1; continue }
            let a = piece.a, last = piece.last, w = piece.w
            if lineSpaced, last > a { lineOther = true }
            // (The automatic space after this stretch, which is no part
            // of a line that ends with it.)
            let after = last > a ? gaps[last - 1] ?? 0 : 0
            let ownSpaces = last > a ? (a ..< last - 1).filter { gaps[$0] != nil } : []
            // (A middle dot set an em — SimSun's "·", hinted East Asian —
            // gives as a mark does: zh-b9af65b5's cell line "元/建筑平米·月"
            // (mode 14, 10.5pt) sets the dot's 10.56 at 8.16 in Word for
            // Windows' print to keep "月" on the line.)
            // (A full-width "！" gives nothing for what follows, as "？" does not, in Word for Windows:
            // zh-ae3d78ee's "…沒差啦！" leaves "也" 4.7pt over with only it to give, its "！" a whole em.)
            let own = (a ..< last).filter {
                (Self._closingUnits.contains(units[$0]) || Self._openingUnits.contains(units[$0]) || wideQuote($0) || wideDot($0)) && !closesUp($0)
                    && !(RichTextTheme.wordWindowsPages && units[$0] == 0xFF01)
                    // (Japanese text, kana in the paragraph: a full stop or comma inside a line, beside no bracket,
                    // gives nothing. jpn-z19433747's Word print holds 34 characters on every line; the zh set squeezes them.)
                    && !(squeezesPauseRule && $0 + 1 < units.count && (units[$0] == 0x3002 || units[$0] == 0x3001 || units[$0] == 0xFF1B) && !Self._openingUnits.contains(units[$0 + 1]) && !Self._closingUnits.contains(units[$0 + 1]))
            }
            let em = a < ems.count ? ems[a] : 0
            // (Less than nothing on a line whose room Word's sum puts a hair
            // short of its width — a line that needs all of it does not
            // fit: see `tieShort` in `_layoutParagraph`.)
            let hair = (onFirstLine ? tieShort.first : tieShort.rest) ? -_px(0.0005)
                : min(em * 0.01, _px(0.002))   // (a stand-in's half em is a hair over half)
            // (On a character grid in Word for Windows, what the marks give
            // for a character has a hundredth of a point to spare: lab hc2 (zh-8d6f702e's
            // package, mode 12 and 14, cells of 15.7927) takes "（3）…结束："
            // with "）" and "，" at half a cell and "：" at half — 0.0072pt
            // over, its 316-twip indent a hair past one cell — and so its
            // "…影响情" (lab z8); at 317 twips, 0.0572 over, or the right
            // indent a twip in, it wraps. Only the marks' give: a line of
            // plain ideographs on a grid fits to the twip (lab g2). Not in
            // a cell: zh-5be7e156's boxed 专栏 tables keep Word's lines only
            // without it. And only on a grid that packs characters tighter
            // than their size (a negative charSpace, -849 there): on one that
            // spreads them Word gives nothing — zh-7654804a's "…最優申請人"
            // with "，" squeezed, cells of 17.0076 (charSpace 4127), 0.0165
            // over, and zh-457a8d62's "…證稱：", 0.0052 over, go down a
            // character short in Word's print; at 0.025 on every grid four
            // of those Control Yuan documents fell 23 to 87 points.)
            let gridGive = theme.wordRules && RichTextTheme.wordWindowsPages && (_grid(i, document).chars ?? 0) < 0 && !inCell
                && !(onFirstLine ? tieShort.first : tieShort.rest) ? _px(0.01) : nil
            // (The half em a line takes at most is Word's to a twentieth
            // of a point: 7.12pt over at 14pt is not taken. The widths
            // are the faces' own now, and the hair would take it.)
            // (Under a twentieth, which is one of Word's units: 16pt
            // text spaced -0.5 takes a character 7.5 over and leaves one
            // 7.55 over — zh-6cd1befe, in a column of 445.25. But as
            // near to it as may be: with Latin digits on the line the
            // sum here is not Word's to the hundredth, and zh-a4b0f6ea
            // has a "《威" taken that comes out a few hundredths over.)
            // (Only where Latin text is on the line and no character grid
            // sets its widths: on one, ours are Word's to the
            // ten-thousandth, digits too, and zh-d68ac84a's
            // "（3）合理性审核…价格是", 7.3248 over against a half em of
            // 7.3232, is not taken by Word — it ends the line at "格",
            // justified.)
            let pieceLatin = (a ..< last).contains { units[$0] < 0x2E80 && !circled(units[$0]) && !isSpace(units[$0]) }
            // (And less than nothing, as `hair`, where Word's sum of the
            // room falls short of it: zh-f39e54b6's 第十四條 sends "日"
            // down that starts exactly half of "按" inside — `tieShort`.)
            let edge = (lineLatin || pieceLatin) && !onCharacterGrid ? min(em * 0.01, _px(0.045))
                : (onFirstLine ? tieShort.first : tieShort.rest) ? -_px(0.0005) : _px(0.0001)
            // (Under `w:kinsoku` 0 a closing mark that closes up with the one
            // after it, which may start the next line, ends this one at its
            // whole width: the pair is parted, and the half it gave is the
            // pair's. zh-72da925e's "…根據應明確說明」；工務局…" sets "」" on
            // p9's first line in Word's print; ours took it at its half,
            // 8.5pt, to the margin exactly.)
            // (So too, line-breaking rules on or off, before an opening mark,
            // which may always start a line: zh-147bdae0's cell line "…〈臺灣給
            // 世界的禮物〉（Taiwan’s…" is 3.9pt over with its "〉" whole, and
            // Word for Windows' print sends "物〉" down; its "…管理系統」（紙本
            // 申報）" sends "統」" down. Ours took the "〉" and "」" at half.
            // Where marks are compressed, a bracket so — not a pause mark, whose
            // half goes all the same: lab `prt` (Word for Windows, zh-7a16a243's
            // package, compressPunctuation, on its grid and off it) takes "積」",
            // "積）" or "積〉" before "（" only with 8pt more room than before "如",
            // at 16pt, and "積、" or "積，" with none; zh-6d1afa56's cell ends
            // "《政府信息公开条例》、" with "《社会" next.)
            let parted = RichTextTheme.wordWindowsPages && last > a && piece.b == last && closesUp(last - 1) && last - 1 < ems.count
                && last < units.count && (kinsokuOff && Self._closingUnits.contains(units[last])
                    || Self._openingUnits.contains(units[last]) && (!squeezes || !Self._pauseMarks.contains(units[last - 1])))
            let pastRoom = pastFrom.flatMap { beyond[$0.tab] } ?? 0
            // (A Latin piece in letter-spaced text, a hundredth of a point: Word sets each character's spacing
            // in its own units, ours adds the exact twentieths, and over a line the sums part by a few
            // thousandths. zh-cf8b03a5's 0-margin cell (spaced -0.8) keeps "…指標2×50%" with the "%" 0.008pt past
            // its 118.2pt line by ours (lab lef cf8: Word's cut and ours fall in the same 0.2pt step); ours sent
            // the "%" down and nine lines after it. Not unspaced text: zh-633792eb's cell leaves a character
            // 0.004 over, and the edge's 0.045 for every Latin line cost 14 documents.)
            let spacedPiece = (a ..< last).contains { k in
                k < runOf.count && (p.runs[runOf[k]].style.letterSpacing ?? lineStyle?.char.letterSpacing ?? _normalChar(document)?.letterSpacing ?? 0) != 0
            }
            let latinSlack = (lineLatin || pieceLatin) && spacedPiece && !onCharacterGrid && !(onFirstLine ? tieShort.first : tieShort.rest) ? max(hair, _px(0.01)) : hair
            var fits = x + w - after - (_yuEndKern[i]?[last - 1] ?? 0) + (parted ? ems[last - 1] / 2 : 0) <= width + pastRoom + latinSlack
            // (What follows a tab to a right stop at the margin that
            // starts inside it runs on past the margin — `runsPast`, T127:
            // zh-ab1ea005's "123.…救济途径？<tab>52" is one line in Word's
            // print, "52" at the margin; ours, counting "52" 16pt over,
            // sent "径？" down with it.)
            let runsOn = !fits && last > a && (pastFrom.map { $0.x < width - 0.01 } ?? false)
            if runsOn, let from = pastFrom {
                fits = true
                // (Set as `measure`'s hang sets it, which the line it was
                // measured on did not reach: the tab takes nothing, and
                // what follows stands on from where it starts, its overrun
                // off the last character's advance. What that cannot give
                // comes off the tab, the number drawn that much into the
                // mark before it — a full-width "？" is blank on its right —
                // rather than its digits over one another.)
                adjust[from.tab, default: 0] -= boxes(from.tab, from.tab + 1)
                let over = from.x + w - width + _px(0.05)
                let lastGives = max(0, boxes(last - 1, last) - _px(0.5))
                if over > 0 {
                    adjust[last - 1, default: 0] -= min(over, lastGives)
                    if over > lastGives { adjust[from.tab, default: 0] -= over - lastGives }
                }
            }
            let traced = Self.debugFit.map { p.text.firstRange(of: $0) != nil } ?? false
            if traced {
                let pt = theme.pixelsPerPoint * scale
                let text = String(decoding: units[a ..< piece.b], as: UTF16.self)
                FileHandle.standardError.write(Data("fit [\(text)] w \(w / pt) x \(x / pt) of \(width / pt) fits \(fits) marks \(marks.count)+\(own.count)\n".utf8))
            }
            // (Under `w:kinsoku` 0 an opening mark may end a line, as a
            // piece of its own, where it fits as it stands — to a twentieth
            // of a point, the grid's sum: zh-72da925e's "…（下稱「", 21
            // characters of 17.0075 in 357.15, ends on it 0.008 over in
            // Word's print. Nothing gives for it: zh-c8eb6e92's cell
            // "定标监督小组人员（签名）" carries the "（", 1.15pt over, to the
            // next line.)
            let openingAlone = (kinsokuOff || squeezeOpen) && last - a == 1 && (Self._openingUnits.contains(units[a])
                || (RichTextTheme.wordWindowsPages && wideQuote(a) && (units[a] == 0x201C || units[a] == 0x2018)))
            if openingAlone, !fits, x + w - width <= _px(0.05) { fits = true }
            // (Fitting by that hair is fitting: the engine allows none,
            // so the last character gives it up.)
            if fits, !runsOn, x + w > width, last > a { adjust[last - 1, default: 0] -= x + w - width + 0.02 }
            // (A piece that opens its line hangs its closing mark all the
            // same: zh-69bbcc3c's paragraph of 48 spaces and "）。", 416pt
            // in a column of 415.6, is one line in Word's print, its "。"
            // 0.4pt past the margin. Ours broke the piece where it would
            // not fit, "。" a line alone. In a cell, where nothing hangs,
            // its marks give: the form's cell line of a 317pt indent, 14
            // spaces and "）。", 9.85pt over, is one line in Word's print.)
            // (Nor a stretch of Han text joined as one word, `_hanJoins`:
            // it goes down as Latin words do — zh-7773163d's "…保障？ 得依保障
            // 法提起救濟？" breaks after the space in Word for Windows' print,
            // where ours hung the "？" and kept the line.)
            let joinedWord = last > a + 1 && hanJoins.contains(a + 1)
            // (Mac Word can compress a body line to keep an opening mark
            // under kinsoku off: zh-72da925e p8 ends in -「, and e0ca7252
            // p22 in 日（. When the previous mark closes up to this one,
            // the alternative line ending restores its blank half; the
            // compression-versus-stretch comparison below counts it.)
            // (Word for Windows squeezes the line's marks for it in a cell too, and
            // in the body: zh-8628cfbe's cell "…每增(減)0.2個百分點加(" (mode 15, kinsoku
            // off, compressPunctuation, 11.5pt) ends on the "(", 9.7pt over, its
            // "，", "(" and ")" given 2.3, 2.3 and 2.4 in Word's print. Not under
            // the alternative kinsoku rules: zh-c8eb6e92's cell carries "（签名）"'s
            // "（" over at 1.15pt.)
            // (Not a full-width quote before 2013's layout: zh-b00fef0d's "…其中" (mode 12) sends its "“" down 4.05 over with two marks to give.)
            // (Under compressPunctuation Word ends a line on an opening mark squeezed by its own blank half at most: lab opn11, zh 8787f4.
            // Less than half an em of room carries it, as it stands.)
            var openerOwn = false
            if squeezeOpen, inCell, openingAlone, last == a + 1 {
                // (In a cell Word does not squeeze or compress for a lone opener: it carries it, fits or not. Lab fit496b, xb jpn 496912 "金額（".)
                openerOwn = true
                adjust[-(a + 2)] = 1
            } else if squeezeOpen, openingAlone, !fits, last == a + 1 {
                openerOwn = true
                if (width - x) * 2 >= w { adjust[a, default: 0] -= x + w - width + 0.02; fits = true }
            } else if squeezeOpen, openingAlone, fits, last == a + 1 {
                // Room for the whole opener: the next ideograph overflows and kinsoku carries it (zh 7f0539, 2c8799).
                adjust[-(a + 2)] = 1
            }
            let macBodyOpener = openingAlone && (RichTextTheme.wordWindowsPages ? !document.hangsHalf && !(legacy && wideQuote(a)) : !inCell)
            let overAtStart = !fits
            if Self.debugFitLog, overAtStart {
                let pt = theme.pixelsPerPoint * scale
                if !loggedParagraph {
                    loggedParagraph = true
                    let flat = String(decoding: units, as: UTF16.self).map { $0.isNewline || $0 == "\t" ? "\u{1F}" : $0 }
                    let head = "FITP\t\(i)\t\(baseWidth / pt)\t\(document.compatibilityMode ?? 12)\t\(document.characterSpacingControl ?? "-")\t\(inCell ? 1 : 0)\t\(p.style.alignment == .justify ? 1 : 0)\t\(kinsokuOff ? 1 : 0)\t\(document.hangsHalf ? 1 : 0)\t\(document.marksCentred ? 1 : 0)\t\(document.balancesSpaceWidth ? 1 : 0)\t\(onCharacterGrid ? 1 : 0)\t\(_inTextBox ? 1 : 0)\t\(String(flat))\n"
                    FileHandle.standardError.write(Data(head.utf8))
                }
                FileHandle.standardError.write(Data("FITO\t\(i)\t\(lineNumber)\t\(a)\t\(last)\t\(x / pt)\t\(w / pt)\t\(width / pt)\t\(after / pt)\t\(marks.count)\t\(own.count)\t\(lineWide)\t\(lineEms / pt)\t\(lineOther ? 1 : 0)\n".utf8))
            }
            if !fits, last > a, (!openingAlone || macBodyOpener), !joinedWord, !openerOwn {
                // (A parted bracket's whole width, as `fits` weighed it, and no
                // hang for it — in Taiwan's convention, where marks are compressed:
                // lab `prt` (zh-7a16a243's package) and that document's p26. Not
                // the mainland's: zh-c97500b6's "…（中办发【2019】5号）" hangs its "）"
                // before "《" in Word's print, and held whole, 899 lines fell.)
                let partedWhole = parted && !kinsokuOff && (!squeezes || document.marksCentred)
                let over = x + w - width + (partedWhole ? ems[last - 1] / 2 : 0)
                let tail = last - 1
                // A closing mark at the end of what comes next may hang
                // past the margin, by as much as it is wide; what is
                // still over, the line's other marks may give.
                // (No more than the mark is wide — a curly quote in a
                // Latin face is under half an em — and half an em at
                // most under the alternative kinsoku rules.)
                // (And not at all under those rules where the document
                // compresses no punctuation: the half that hangs is the
                // mark's own, given up.)
                // (A mark that ends the paragraph neither hangs nor gives
                // its own half, where the document names its own characters
                // that may not start a line — `w:noLineBreaksBefore`; the
                // line's other marks may still give for it. Labs `hang1`–
                // `hang6` in zh-ae3d78ee's package, 2026-10-14: "…你花最多的。"
                // over by 1 to 15pt goes to the next line as "的。" with a
                // "？" — which never gives — as the line's only other mark,
                // whatever the alignment, spacing, face or kerning; with a
                // "，" on the line it is taken, the comma giving; with text
                // after the mark in the paragraph it hangs in every case.
                // Documents without the list hang a paragraph's last mark
                // as any other — zh-5901e2b0's, zh-7dc3afad's — and the
                // rule without the condition cost them 50 points each; so
                // do those with the Simplified list (zh-a4b0f6ea, `zh-CN`,
                // 81.7% to 30.2 under it) and those with the Traditional
                // list from Word 2013's layout on (zh-4b8e0abc, mode 15,
                // whose final marks Word hangs by 3.5pt). It holds for the
                // `zh-TW` list before that layout: zh-ae3d78ee (mode 14)
                // 84.4% to 100, zh-64044a1d (mode 11) +5.6.)
                let listed = document.keptSettings["w:noLineBreaksBefore"]?.containsSubstring("w:lang=\"zh-TW\"") ?? false
                // (Without the list, in Taiwan's Chinese, a centred mark that
                // ends the paragraph neither hangs nor gives anything, the
                // line's other marks giving their halves: lab `hang` in
                // zh-a5745784's package (Word 16, mode 14, zh-TW, 12pt) keeps
                // "…大隊長代理。" or "…代理：", one comma on the line, to 6.0pt
                // over, "…資格者，…資格：", two, to 12.0 — and with text after
                // the colon to 18.0, its hang and the half before it. In the
                // body, and of a paragraph not justified where the document
                // compresses punctuation: zh-06c46ba9's justified ones, and
                // zh-6c6adfde's that compress none, hang theirs in Word's
                // print; a cell's last mark gives its half, lab `pe`.)
                let centredFinal = !listed && !inCell && squeezes && p.style.alignment != .justify && document.marksCentred && Self._centredUnits.contains(units[tail])
                // (Only where it might have hung: under `w:overflowPunct`
                // off it gives its half as a cell's does — zh-749cb15a's
                // "…教育訓練活動。" (style k4a, overflowPunct 0, zh-TW
                // list, mode 14) is 2.1pt over and one line in Word's
                // print, its "。" set 12.3 of 14.4; ours sent "動。" down,
                // and the page ran a line long.)
                // (In the body: a cell's last mark gives its half under the
                // list too, as lab `pe` has it without — zh-31d580df's
                // review table (zh-TW list, no mode) ends a cell line
                // "…施作項目與數量。" 2.7pt over in Word's print, the "。"
                // squeezed; ours sent "量。" down.)
                // (Not under `w:useAltKinsokuLineBreakRules`: there the
                // paragraph's last mark gives up to its half — lab `hangp`
                // (macOS-doc, Word for Mac): zh-12c4f07a's "…物產館)。"
                // (Taiwan's list, alternative rules) holds to its "。"
                // 6.39pt narrower and goes down from 6.59, in modes 11, 12
                // and 14, with a "？" on the line or not; zh-ae3d78ee's
                // "…你花最多的。" gives nothing as it is and its half with
                // the switch set; ours sent "館)。" down at 1.39.)
                let altFinal = theme.wordRules && document.hangsHalf && squeezes
                // (Nor at compat 14 where the eastAsia language is zh-CN or ja-JP, whatever list the file keeps: lab comma-hang7 v4/v7,
                // a zh-TW list under those languages hangs the paragraph's last 。 as the mainland's does.)
                let holdsFinal = (listed && !inCell || centredFinal) && p.style.eastAsian["w:overflowPunct"] != "0" && !altFinal
                    && !(RichTextTheme.wordWindowsPages && theme.wordRules && (document.compatibilityMode ?? 12) == 14 && document.markSqueezeEm >= 0.5)
                    && (document.compatibilityMode ?? 12) < 15
                    && tail == (units.lastIndex(where: { !isSpace($0) }) ?? -1)
                // (From 2013's layout on a Latin comma hangs too, whole:
                // lab `hc2` (Word 16, mode 15, Cambria 14 in a justified
                // paragraph of East Asian layout) takes "pusat," 9.5pt
                // over and not 10, "pusat" 7.0 and not 7.5 — the comma's
                // 2.87 the difference; zh-4b8e0abc's Indonesian line ends
                // "pusat," 2.7pt past the margin in Word's print.)
                // (And a Latin closing parenthesis: zh-e0ca7252 (mode 15)
                // ends "…免載於招標文件)" with its ")" 4.2pt past the margin
                // in Word's print, "件" squeezed in before it; ours sent
                // "件)" to a line of its own and page 26 ran a line long.)
                // (Before it too, a ")" after an East Asian character: zh-28416dc9
                // (mode 12, doNotCompress, 標楷體 14pt) ends "…委外機構(公 司)"
                // with its ")" 4.8pt past the margin in Word's print, "司"
                // inside; ours broke at the space before "司".)
                // (Word for Mac hangs a Latin "?", "." or ")" at a justified
                // Thai line's end, mid-paragraph too: lab `tthai`
                // (zh-6a4fc013's p17 heading "…ใช่หรือไม่?", Browallia
                // bold) keeps it one line with its "?" 7pt past the margin
                // — "." and ")" the same, its run's w:cs or not — and wraps
                // it set left or under overflowPunct 0. Word for Windows
                // wraps it.)
                let macThai = !RichTextTheme.wordWindowsPages && p.style.alignment == .justify
                    && [0x3F, 0x2E, 0x29].contains(units[tail]) && units.contains { $0 >= 0x0E01 && $0 <= 0x0E5B }
                // (And a Latin "," at a justified line's end, before Word
                // 2013's layout too, in Word for Mac: lab `t3fe` (zh-3fe252ff's
                // p22 rule paragraph, mode 14) holds "…31行3栏>0," 3.5pt past
                // the margin, 4.5 one step narrower, the space after it or
                // not; Word for Windows wraps it there. That file compresses
                // nothing under the alternative kinsoku rules, where no
                // mark of ours hangs: this one does.)
                let macComma = theme.wordRules && !RichTextTheme.wordWindowsPages && p.style.alignment == .justify && units[tail] == 0x2C
                // (Where a mark may hang only its inked half and nothing is compressed, a half-width "," or "."
                // is all ink and hangs whole, in Word for Windows: zh-3fe252ff (mode 14, useAltKinsokuLineBreakRules,
                // doNotCompress) ends "…有账面价值的资产," "…应选择“21." and "…提示）," with the stop past the margin in
                // Word's print, which hangs no full-width mark there; ours hung nothing and sent the last word down.)
                let halfStop = theme.wordRules && RichTextTheme.wordWindowsPages && document.hangsHalf && !squeezes
                    && (units[tail] == 0x2C || units[tail] == 0x2E)
                let latinComma = halfStop || !legacy && (units[tail] == 0x2C || units[tail] == 0x29)
                    // (Compat 15: a final "." after a Latin letter stays while its origin is inside the margin: kor 59e77f "shows.", ff493b "electricity.".)
                    || !legacy && units[tail] == 0x2E && tail > 0 && ((units[tail - 1] | 0x20) >= 0x61 && (units[tail - 1] | 0x20) <= 0x7A)
                    || units[tail] == 0x29 && tail > 0 && units[tail - 1] >= 0x2E80 && (!hangulStop || hangulParen)   // (b6f6c7d4: a Korean line with digits and only stops to hang keeps ")" whole, as Word)
                    // (… a "," too: zh-9bcea239's "…少于6个月的," (mode 12, Times) is one line in Word for Windows' print, its "," 3.99 past the margin.)
                    || units[tail] == 0x2C && RichTextTheme.wordWindowsPages && tail > 0 && units[tail - 1] >= 0x2E80
                    || macThai || macComma
                    || document.hangsLatinStops && RichTextTheme.wordWindowsPages && legacy && (units[tail] == 0x2E || units[tail] == 0x2C)
                    || latinStops && Self._latinStopUnits.contains(units[tail]) && !_afterHyphenPiece(units, tail)
                    // (Lab hang1 tested words that start after a space; Word moves a hyphen's second piece "ig." whole: 7b3ae3a6 "2021-ig.".)
                    // (A Korean word's own stop hangs: ecc32adb's "…포함된다." ends past the margin, the word whole.)
                    || RichTextTheme.wordWindowsPages && wordRules && (units[tail] == 0x2E || units[tail] == 0x2C) && tail > 0 && units[tail - 1] >= 0xAC00 && units[tail - 1] <= 0xD7A3
                // (Before Word 2013's layout, in a document that compresses
                // punctuation, Taiwan's centred marks give nothing at a
                // line's end to be taken, and the paragraph's own last one
                // does not hang (see `kept`): lab `lp` (Word for Mac,
                // zh-ff93733d's package, 標楷體→YaHei 14pt justified, 30
                // ideographs and "乙" before the mark; no mode and mode 14
                // alike): "乙；" mid-paragraph under overflowPunct 0 goes
                // down a whole em sooner than an ideograph would (mode 15
                // gives the "；" its half); "乙。" ending the paragraph goes
                // down a whole em sooner, and under overflowPunct 0 half
                // an em — there it gives its half, as zh-749cb15a's
                // "…教育訓練活動。" does. zh-ff93733d's "…調查結果。" is
                // carried whole in Word's print so. A bracket, with a blank
                // half, still gives it (zh-fec5fa30's cells end "民政局
                // （處）"); a document that compresses nothing, or the
                // mainland's, hangs its final marks as any.)
                // (In the body: a cell's last mark gives its half, lab `pe`,
                // and zh-ff93733d's cells end "…計算諮詢次數。" so.)
                let centredEnd = (document.compatibilityMode ?? 12) < 15 && squeezes && !inCell && document.marksCentred
                    && Self._centredUnits.contains(units[tail])
                let paragraphEnd = tail == (units.lastIndex(where: { !isSpace($0) }) ?? -1)
                // (From 2013's layout, a mark another closes up to — "）。" —
                // gives the line half an em for hanging, not its whole: labs
                // `u5`/`u6` (Mac, Word 16, zh-505b9619's package: mode 15,
                // 14pt, three marks on the line) take "…（未載明者為3日）。" with
                // the need, over a whole em's hang, up to 14.0 and not from
                // 14.25 — the marks giving a third each of it and half an em
                // more — and draw the "。" inside the margin, "）" 3.5 wide.
                // Only on a line with word spaces, whose marks give by the
                // older test: on one without, the share test with a whole
                // em's hang is Word's — zh-7488a70f's "…（民間21項、機關16
                // 項）。" is one line in its print. u5's blanks as "某" left
                // Word's limit where it was and ours lower: not found.)
                let closedUpTo = theme.wordRules && !legacy && squeezes && lineOther && tail > a && closesUp(tail - 1)
                // (Nor a full-width "？" that ends the paragraph where the
                // marks are compressed: labs `qh`/`qe` (Word for Windows) keep
                // zh-ab1ea005's heading "…税收优惠？" (mode 14, zh-CN, 16pt) to
                // 7.91pt over, the line's half-em squeeze, and refuse it from
                // 8.01 — under zh-TW, jc both, hint eastAsia, 標楷體 or kern 2
                // the same — while with doNotCompress it hangs whole, to
                // 15.91, as zh-eccb2003's "…共識？" does at 14pt to 13.95. With
                // text after it the "？" hangs as any: zh-ae3d78ee's "…這回
                // 事嘛？" and zh-424775e4's "…不说为好？", compressed both.)
                // (Nor, where it may hang only half of itself — the half
                // that is ink, `w:useAltKinsokuLineBreakRules` — a centred
                // mark anywhere: it has no blank half to hang by. Lab `pc`
                // (Word for Windows, zh-12c4f07a's package, no mode,
                // zh-TW, 標楷體 13pt): "…履行本契約、" sends "約、" down from
                // 0.15pt over, left or justified, while "、" inside the
                // line gives its half; without that switch the "、" hangs
                // whole, to 12.5 over. zh-12c4f07a p11 so; ours hung it.)
                // (Nor, from 2013's layout, a closing bracket that ends the
                // paragraph where marks are compressed: it gives its half as
                // any other. zh-20c1d74a's "…督導考核及管理等）" (mode 15,
                // 12.5pt) sends "等）" down in Word's print, which ours took
                // 9.55 over with the "）" hung. Not the pause marks: with
                // every final "。" kept so the same document ran a page long.
                // Nor a Latin ")": zh-e0ca7252's "…免載於招標文件)" hangs it.)
                // (Nor, from 2013's layout where marks are compressed, an
                // East Asian mark after a Latin letter or digit: labs t170e
                // and t175 (Windows 01QbbApP, Word for Windows; zh-15f60bac's
                // and zh-021b8feb's packages, mode 15, 標楷體) — zh-021b8feb's
                // "…與輔具試用、" hangs its "、" from about 21pt over at 14pt,
                // its marks having given all they can, and goes down past
                // 23; with "6" for "用" it never hangs and goes down at
                // 12.5. zh-15f60bac's "…詳表5第4、6、" leaves "6、" 18.75 over;
                // ours hung the "、" and squeezed the rest.)
                let afterLatin: Bool = {
                    guard squeezes, !legacy, units[tail] >= 0x2E80, tail > 0 else { return false }
                    let u = units[tail - 1]
                    return (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A)
                }()
                // (Nor, in a face Word compresses nothing in, the paragraph's
                // last mark: Word for Windows sends zh-57f1de0d's "…基本物资。 "
                // down as "资。", and its "…整洁、卫生。 " and "…信息等）。 "
                // so — and, once the face's own digits are counted, its
                // "…良好互动；" with nothing after it, in both Words' prints;
                // the face's marks hang there only inside a paragraph. Not in
                // other faces: there Word hangs them — zh-4c5da793 and
                // zh-2b955411 fell to 16 and 36 with every such mark kept in.)
                let spacedEnd = paragraphEnd && uncompressed(tail)
                // (Under `w:kinsoku` 0 before 2013's layout a closing mark that is a piece of its own
                // hangs all the same, and opens the next line only where the line is already full: labs
                // `kq`, `kq2` (Word for Windows, modes 12 and 14, 16pt, direct or on Normal): "，", "、" and
                // "”" stay from 15.5 over with any number of marks on the line, and go down at 16.
                // zh-b00fef0d's "…协同更高效" is squeezed full for its "效", and its "、" opens the next.)
                let kinsokuHang = RichTextTheme.wordWindowsPages && legacy && fitted && kinsokuOff && !inCell && !turned && last == a + 1
                    && x < width - _px(0.01) && units[a] >= 0x2000 && p.style.eastAsian["w:overflowPunct"] != "0"
                // (Nor a bracket parted from the opening mark after it: lab `prt`'s
                // body lines take "積」" before "（" only where the line holds it whole.)
                let hung = (hangs || latinStops || kinsokuHang) && !partedWhole && !holdsFinal && !spacedEnd && !(centredEnd && (paragraphEnd || document.hangsHalf)) && !(squeezes && paragraphEnd && units[tail] == 0xFF1F)
                    && !(squeezes && paragraphEnd && !legacy && units[tail] >= 0x2E80
                         && !Self._pauseMarks.contains(units[tail]) && units[tail] != 0xFF0E)
                    && (Self._hangingUnits.contains(units[tail]) || latinComma) && (squeezes || !document.hangsHalf || macComma || halfStop)
                    && !runRulesOff(tail) && !afterLatin
                    // (Nor a 、 or 。 with text after it where the pause rule holds: lab `sqreal`
                    // (jpn-z19433747's abstract, 65 right indents in 0.25pt steps) opens the next
                    // line with it at every indent, where it would hang 4.7 to 7.7 pt over.)
                    && !((squeezesPauseRule || noHangJa) && !paragraphEnd && (units[tail] == 0x3001 || units[tail] == 0x3002))
                    // (Nor a full-width percent sign in Taiwan's Chinese, whose own list leaves it out
                    // of what may not start a line: it is no closing mark there, and does not hang.
                    // zh-ab9cbe66's "…分署25％(不含)－55％(含)" sends "％(含)" down in Word's print
                    // with the sign 0.23 over; ours hung it.)
                    && !(units[tail] == 0xFF05 && wordRules && RichTextTheme.wordWindowsPages && document.keptSettings["w:noLineBreaksBefore"] == nil && Self._traditionalChinese(document))
                    // (Nor, before 2013's layout where marks are compressed, a
                    // Latin closing quote: lab `z01` (Word for Windows,
                    // zh-015abfaf's package, mode 14, 16pt) takes "…比学赶帮超”"
                    // only while its "，" can give what the pair stands over —
                    // 7.14 at a right indent of -6pt, the line ending at the
                    // margin — and never hangs the 6.57pt "”"; ours hung it and
                    // took the pair 6pt further. Mode 15 takes it further.)
                    && !(legacy && squeezes && document.hangsHalf && (units[tail] == 0x201D || units[tail] == 0x2019) && !wideQuote(tail))
                    // (Nor a full-width closing quote the run sets in the Latin slot, where a mark may squeeze: lab `ql`
                    // (Word for Windows, zh-e61c3dff p1, mode 14, useAltKinsoku, 仿宋_GB2312 with w:hint="default"):
                    // "…“科技特派团”、“科技副总”" 14.9 over keeps its last "”" inside the margin and squeezes the "”" and
                    // "、" before it 5.3 each; hinted East Asian (E) it hangs 8 and squeezes less. Only margin 0 differs
                    // of the 98 prints.)
                    && !(wordRules && RichTextTheme.wordWindowsPages && legacy && squeezes && document.hangsHalf && !paragraphEnd
                         && (units[tail] == 0x201D || units[tail] == 0x2019) && tail < runOf.count
                         && (p.runs[runOf[tail]].style.fontHint ?? lineStyle?.char.fontHint) != "eastAsia")
                    // (Half the mark as the grid of characters sets it, its
                    // em and the grid's addition, under the alternative
                    // kinsoku rules: lab q18 (Word for Windows, zh-015abfaf's
                    // package, mode 14, a line of ideographs and "）" with its
                    // right indent stepped by two twips) takes the mark while
                    // it hangs 7.874 at 16pt with charSpace -1032, 5.874 at
                    // 12pt, 7.756 at -2000 — never the em's 8 or 6; off the
                    // grid 8 and 6.)
                    ? (closesUp(tail) || document.hangsHalf || closedUpTo
                       ? min((ems[tail] + (document.hangsHalf && tail < runOf.count && !runsOffGrid[runOf[tail]] ? gridAdd : 0)) * 0.5, boxes(tail, tail + 1)) : min(max(ems[tail], boxes(tail, tail + 1) - (gaps[tail] ?? 0)), boxes(tail, tail + 1))) : 0
                // (From 2013's layout, where marks are compressed, the
                // paragraph's last mark hangs only once the line's marks,
                // itself among them, and its automatic spaces cannot give
                // what the line needs; short of that it stays inside, and
                // the character is taken where the marks and spaces give it
                // by the share test (see `takenFirst`; on a line with word
                // spaces by theirs, as zh-505b9619's "…（未載明者為3日）。",
                // 27.15 over, which Word leaves). zh-e0ca7252's "…依第17款
                // 辦理。" is 21.55pt over, two commas and the "。" able to give
                // 21 and two such spaces 1.75, and Word sends "理。" down with
                // the commas whole; ours hung the "。" and squeezed the commas
                // 3.8 each. zh-505b9619's "…付款期限為30工作天。" is 18.9 over
                // with three marks' 21, and Word takes it squeezed, the "。"
                // inside the margin; zh-021b8feb's "…審查及核定。" is 18.2 over
                // with two marks' 14, and Word hangs its "。" from 1.4 inside
                // the margin, the "、" squeezed. Lab t175 (Windows 01QbbApP,
                // Word for Windows, zh-021b8feb's package: mode 15, 標楷體
                // 14pt) stages a mark inside a paragraph so too — its marks
                // squeezed to about 20.5 over, the last "、" hung only from
                // 21 — but there ours hangs sooner and ends the same lines:
                // zh-505b9619's "…以供隨時查閱。" and zh-1b74ed91's "…前3名，"
                // keep their hang and squeeze.)
                let olderSqueezed = legacy && RichTextTheme.wordWindowsPages && document.balancesSpaceWidth && !paragraphEnd && !kinsokuOff
                let squeezedFirst: Bool = {
                    // (Word for Windows' older layout, a line of brackets and a closing 、 inside a paragraph: zh-de97afa7's
                    // "据《…》(…、" is 8.7 over; Word squeezes 《 and 》( 4.3 each and ends the 、 inside the margin; ours hung it. Lab zde.)
                                        guard hung > 0, over > hung + 0.0001 && !olderSqueezed || olderSqueezed && over >= hung / 2 && over <= hung + 0.0001, squeezes, paragraphEnd && !legacy || olderSqueezed, !inCell, !document.hangsHalf else { return false }
                    // (Not a Latin ")" or ",": it gives nothing, so it hangs
                    // whole and the rest is weighed as any line's.
                    // zh-e0ca7252's fresh Mac print (mode 15) takes
                    // "…免載於招標文件)" 14.25pt over, three marks able to give
                    // 20.6: its ")" hung, "件" needs 9.8, which the share test
                    // takes; held to the whole 14.25 it refused, and p26 on
                    // ran a line late.)
                    guard !(latinComma && units[tail] < 0x2E80) else { return false }
                    let muted: (Int) -> Bool = { o in
                        (olderSqueezed && o == tail) || RichTextTheme.wordWindowsPages && runRulesOff(o)
                            && (Self._pauseMarks.contains(units[o]) || [0x201C, 0x201D, 0x2018, 0x2019].contains(units[o]))
                    }
                    let give = (marks + own).filter { !runLanguageNone($0) && !muted($0) }.reduce(0.0) { sum, k in
                        sum + (wideQuote(k) ? (ems[k] + quoteSpacing(k)) / 2 : (boxes(k, k + 1) - (gaps[k] ?? 0)) / 2)
                    }
                    let verdict = over <= (olderSqueezed ? give : (spaces + ownSpaces).reduce(give) { $0 + (gaps[$1] ?? 0) / 2 }) + hair
                    #if os(Linux)
                    if olderSqueezed, getenv("STARLING_SQ") != nil {
                        let part: (Set<Int>) -> Double = { u in (marks + own).filter { !runLanguageNone($0) && !muted($0) && u.contains(Int(units[$0])) }.reduce(0.0) { $0 + (boxes($1, $1 + 1) - (gaps[$1] ?? 0)) / 2 } }
                        let pauses = Set(Self._pauseMarks.map { Int($0) })
                        let sp = (spaces + ownSpaces).reduce(0.0) { $0 + (gaps[$1] ?? 0) / 2 }
                        fputs("SQ tail=\(String(UnicodeScalar(units[tail]) ?? "?")) over=\(over) hung=\(hung) give=\(give) pause=\(part(pauses)) spaces=\(sp) nmarks=\((marks + own).count) -> \(verdict)\n", stderr)
                    }
                    #endif
                    return verdict
                }()
                let hang = squeezedFirst ? 0 : hung
                // (Whole, a spaced mark hangs its spaced width: lab `p01`
                // (macOS-doc, zh-01bbcd4d's package, 16pt spaced to 17) hangs
                // the "。" of "…组织成员”。" from the margin on, 17 past it.)
                // (No hair over the hang: lab `hc`, a two-character indent
                // and 28 ideographs and "。" on zh-d68ac84a's grid, the
                // mark 0.003pt past its em at 586 twips of indent, is
                // wrapped by Word and hangs at 580.)
                // (A line-end comma, full stop or enumeration comma on a line whose marks squeeze, Word for
                // Windows: lab `comma-hang3` (zh-e0ca7252's "…備，", w:right stepped) keeps the pair while
                // 5.76pt is left after "備" and carries it at 5.26: the mark squeezed to 0.76 em and hung
                // 0.28 em past the margin, so it may stand about half an em over, not the whole em. Lab `comma-hang4` (16 pt, 0.25 pt steps) keeps it at 7.95 pt left (8.05 over) and carries it at 7.75 (8.25): the limit is half an em plus 0.24 pt, a fraction of the size, not a fixed 3.5 pt; two sizes tested.)
                let commaHalfHang = theme.wordRules && RichTextTheme.wordWindowsPages && squeezes && !inCell && !paragraphEnd
                    && ((document.compatibilityMode ?? 12) >= 15 || ((document.compatibilityMode ?? 12) == 14 && document.markSqueezeEm >= 0)) && p.style.pBdrElement && document.lineGridPitch == nil
                    && p.style.eastAsian["w:overflowPunct"] != "0" && last == a + 2 && tail == a + 1
                    && (units[tail] == 0xFF0C || units[tail] == 0x3002 || units[tail] == 0x3001)
                    && over > ((document.compatibilityMode ?? 12) >= 15 ? em * 0.50 + 0.24 : ((marks.isEmpty && document.marksCentred ? -1 : em * document.markSqueezeEm * Double(marks.count + 1) + 0.24))) && hang > 0 && over <= hang + 0.0001
                if commaHalfHang { RuleTrace.hit("e0ca7252-comma-hangs-by-half-em-only") }
                // (Compat 14, zh-CN: a pair past the half-em limit is kept where the line's automatic spaces give the
                // difference — zh-16e0a12a's "…补贴，" is 11.5 over, the limit 8.24, and Word sets the two gaps beside
                // its "1" 2.3 each, not 4: just the 3.3 it needs. Measured per gap in that print, p4 and p30.)
                let digitGapSqueeze: Double = commaHalfHang ? Self._digitGapSqueeze(document, over: over, em: em, marks: marks.count, gapOf: { gaps[$0] ?? 0 }, spaces: spaces + ownSpaces, hair: hair) : 0
                if digitGapSqueeze > 0 {
                    let all = spaces + ownSpaces
                    let total = all.reduce(0.0) { $0 + (gaps[$1] ?? 0) }
                    for k in all { adjust[k, default: 0] -= (gaps[k] ?? 0) / max(0.001, total) * digitGapSqueeze }
                    adjust[tail, default: 0] -= over - digitGapSqueeze + 0.02
                    fits = true
                } else if hang > 0, over <= hang + 0.0001, !commaHalfHang {
                    // (All of it, the hair too: the engine has none.)
                    adjust[tail, default: 0] -= (!squeezes && !turned && wordRules && RichTextTheme.wordWindowsPages && !document.hangsHalf ? hang : over + 0.02)
                    fits = true
                } else if (squeezes || topOnly) && !(commaHalfHang && (document.compatibilityMode ?? 12) == 14) {
                    // (Its own marks give too: the same form's "       ），"
                    // after a 344pt first-line indent, 4.25pt over, is
                    // one line in Word's print, the "）" set 4.3pt close.)
                    // Word takes the next character where it is half an
                    // em or less too wide for the line, and then all of
                    // what cannot be parted from it (an opening mark's
                    // word), as long as the line's marks can give that
                    // much: half an em each, shared evenly.
                    // (The mark at the end is not one of them where it
                    // hangs — nor, before Word 2013's layout, in a cell,
                    // where it would have hung: there the line's other
                    // marks give and the last keeps its em; from 2013's
                    // on it gives its half like the rest.)
                    // (That was a document in Taiwan's Chinese. In the
                    // mainland's — the language Normal names for East
                    // Asian text — the last gives its half before 2013's
                    // layout too: twenty ideographs and a comma are
                    // taken at 20.5 ems, with a comma among them at 21,
                    // and under `zh-TW` at 21 and 21.5. Measured
                    // 2026-10-13, left and justified, with and without
                    // kerning, cell margins and nine compatibility
                    // switches, none of which moved it.)
                    // (… except the paragraph's own last mark, which gives
                    // its half there too: lab `pe`, zh-89385c94's package,
                    // Word for Windows — eight ideographs and a comma, a
                    // full stop, a bracket, a quote, 、 or ； are taken up
                    // to 7.0pt over at 14pt and not at 7.5 where they end
                    // the paragraph, and not even 0.55 over where text
                    // follows. Its cells end "納入課程教學參據。" so.)
                    // (… or a line: before a line break the mark is the
                    // last of what the line could hold, as at the
                    // paragraph's end — zh-e6d54ae4's cell line "…上網服
                    // 務。" before its break is taken 8.2pt over in Word.)
                    let endsParagraph = units[(tail + 1)...].first(where: { !isSpace($0) }).map { $0 == 0x0A || $0 == 0x2028 || $0 == 0x0B } ?? true
                    // (A bracket gives its half there all the same — it
                    // has a blank half, where Taiwan's centred "，。、" have
                    // none to give: lab `cb`, zh-9e08ed28's package, a cell
                    // line of "…服務團」" 0.5pt over is taken, "…團，",
                    // "…團。", "…團、" go down; "）" and "』" as "」".)
                    // (Under that list the last mark gives its share where
                    // another mark on the line gives too: zh-64044a1d's
                    // "…措施事宜。" 6.15pt over sets "，" and the final "。"
                    // 3.1 and 3.0 narrower in Word's print. Alone — the
                    // labs' line with a "？", which gives nothing — it
                    // gives nothing either.)
                    // (From 2013's layout, under `w:useAltKinsokuLineBreakRules`,
                    // a mark hangs by the half of it that is ink and its blank
                    // half gives like any other's: zh-c2c92639 (mode 15) ends
                    // "…保证车辆冲洗干净；" 16.75pt over, "；" 5.25 past the
                    // margin and two commas giving 11.0, where ours sent
                    // "净；" down. Not before it: zh-1563bd74 (mode 14) leaves
                    // "…民政部门，" with one comma, 21.75 over.)
                    // (At the paragraph's end only where it is the line's
                    // only mark: with another on the line giving, it gives
                    // its share — zh-64044a1d's "…措施事宜。" sets "，" and the
                    // final "。" 3.1 and 3.0 narrower in Word's print. Inside
                    // the paragraph it gives nothing whatever else does:
                    // zh-749cb15a's "…人民利益攸關之功能性及專業性國際組織；"
                    // and the Mac's "…等，" with two commas are carried.)
                    let alone = !(marks + own).contains { $0 != tail }
                    let centredKept = centredEnd && (paragraphEnd ? alone && p.style.eastAsian["w:overflowPunct"] != "0" && !altFinal : true)
                    let kept = centredKept || (squeezedFirst && olderSqueezed) || (hang > 0 && !(document.hangsHalf && squeezes && (document.compatibilityMode ?? 12) >= 15 && !closesUp(tail))) || (holdsFinal && (centredFinal || !(marks + own).contains { $0 != tail })) || (legacy && inCell && !document.marksSitLeft && Self._centredUnits.contains(units[tail]) && !endsParagraph)
                    // (A mark in text whose East Asian language is stated
                    // as none gives nothing: zh-0513f641's body style "ad"
                    // says `w:eastAsia` x-none, and Word's print leaves "維"
                    // 5.7pt over a line whose "：" could give 7 — lab c0513
                    // (Mac, Word 16): with a comma, under zh-CN defaults,
                    // 2.9pt over, unnumbered, the same; the style saying
                    // zh-TW, the colon gives and "維" is taken. Not en-US,
                    // whose marks give in Word for Mac: zh-c5b5087b's en-US
                    // body squeezes its commas in its print.)
                    // (Word for Windows' pause marks and curly quotes give
                    // nothing in text whose East Asian language is no
                    // Chinese, Japanese or Korean: zh-c5b5087b's lines are
                    // 27 characters at their full widths in its print, the
                    // commas unsqueezed and one starting the next line,
                    // where ours took a 28th with a comma at its half and
                    // ran a page long.)
                    // (Word for Mac's the same, in a print from a fresh
                    // Word: zh-c5b5087b's reference (a3304812, its Normal
                    // `w:eastAsia` en-US, mode 14, kinsoku off) sets every
                    // "，、。；" from p2 on at its whole em, one opening a
                    // line. Its older Mac prints squeezed them up to a page
                    // that moved from session to session — p5, p6, p6, p10
                    // in four prints — and none past it: Mac Word's own
                    // language detection tagging the text as it goes, not
                    // a rule of the file. zh-264d7516, zh-efd9229a and
                    // zh-51af781b go to their Mac prints with it too.)
                    // (Nor, in Word for Windows, a curly quote its run does not
                    // hint East Asian: it is set in the Latin slot, full-width
                    // or not by the face there. Lab e5t (zh-e5eb092a's package,
                    // mode 14, compressPunctuation, zh-CN): its unhinted quotes
                    // in a 宋体 hAnsi (Normal (Web)) take "府”，" only while
                    // "…府”" fits with every “ ” at 12.0, where the same quotes
                    // as 《》 let "》" give half its em; ours squeezed four
                    // quotes 1.8 each and took the line. The Word-for-Windows
                    // prints that squeeze full-width quotes have them hinted.)
                    let latinSlotQuote: (Int) -> Bool = { o in
                        wordRules && RichTextTheme.wordWindowsPages && o >= 0 && o < runOf.count
                            && [0x201C, 0x201D, 0x2018, 0x2019].contains(units[o])
                            && (p.runs[runOf[o]].style.fontHint ?? lineStyle?.char.fontHint) != "eastAsia"
                    }
                    // (Nor a mark before a tab, in a paragraph of Thai: lab `thq`
                    // (Windows, zh-6a4fc013's p26 question, "…ที่ 6 ：" and a tab) sets
                    // the "：" at its full 15.96 at every width, the line's overrun
                    // taken from the spaces.)
                    let thaiParagraph = theme.wordRules && RichTextTheme.thaiBreaksAtSpaces
                        && units.contains(where: { (0x0E01 ... 0x0E5B).contains($0) })
                    let windowsMuted: (Int) -> Bool = { o in
                        runRulesOff(o)
                            && (Self._pauseMarks.contains(units[o]) || [0x201C, 0x201D, 0x2018, 0x2019].contains(units[o]))
                            || latinSlotQuote(o)
                            || thaiParagraph && o + 1 < units.count && units[o + 1] == 0x09
                    }
                    // (Nor, in Word for Windows, an opening mark right after a
                    // space on a line a tab stands on: lab p10 (zh-015abfaf's
                    // "17.手工嵌线技能竞赛<tab>                 （文登区开发区）",
                    // mode 14, a grid) leaves "区）" for the next line until
                    // the room is the line as set less the hang, the "（"
                    // whole — with 12 to 17 spaces after the tab, the tab
                    // wider or narrower. Without the tab it gives its blank
                    // half, and after an ideograph with it.)
                    let afterTabSpace: (Int) -> Bool = { o in
                        RichTextTheme.wordWindowsPages && o > 0 && units[o - 1] == 0x20 && Self._openingUnits.contains(units[o])
                            && (lineTabbed || (a ..< max(a, o)).contains { units[$0] == 0x09 })
                    }
                    // (Taiwan's full-width colon, mid-line, does not give for a paragraph's
                    // last mark hung past the margin when the character before it is more
                    // than 3pt over: zh-505b9619's "…第5點之人員。" (mode 15, zh-TW, 14pt,
                    // 5.35 over) sends "員。" down in Word's print with the "：" full
                    // width, where ours squeezed it and hung the "。". Under 3pt it gives:
                    // zh-d746674a's "…編碼意義等。" is 1.6 over and takes it.)
                    var all = (marks + own).filter { (!kept || $0 != tail) && !(hang > 0 && over - hang > 60 && paragraphEnd && theme.wordRules && !legacy && document.marksCentred && (document.compatibilityMode ?? 12) >= 15 && $0 != tail && units[$0] == 0xFF1A) && !runLanguageNone($0) && !windowsMuted($0) && !afterTabSpace($0) && (!topOnly || leadOpeners[$0] != nil) }
                    // (A closing mark that opens the line is not squeezed when it is the only mark that could give:
                    // zh-72da925e p8 sends "大" down in Word's print where ours took it 0.0014 short from the opening "，"
                    // (8.5pt over; Word's "，" stands whole, 17.38). With another mark to give beside it, it gives too:
                    // zh-c15af02e's "，已違反…，應依" has its opening "，" at 10.2 in Word's print. Under 5pt over (zh-9e08ed28 has one at 2-5pt that gives), the line
                    // fits as it stands in Word (zh-72da925e's "，主要係依據…24417號", 0.33pt over, "，" whole at 16.9): our
                    // widths run a little long there, so the mark gives for the same break.)
                    // (From 2013's layout on too, in the body: zh-4b8e0abc
                    // (mode 15) takes "PCR(共" 12.1 over with a full-width
                    // colon at its half and the four automatic spaces
                    // between ideographs and Latin set at 2.3 of their
                    // 3.5 — the marks first, the spaces the rest.)
                    // (In a cell from 2013's layout, the automatic space just
                    // before what is taken, and no other: zh-db07d44e (mode 15,
                    // zh-TW 12pt) ends a cell line "…加(減)1分。" at its edge in
                    // Word's print, the "，" and "。" at their halves and the
                    // space between "1" and "分" 0.53 narrower — 12.53 of need;
                    // zh-6e7ff836's "…(80分)比較，相" leaves "相" 6.39 over, its
                    // comma's 6 short and the line's spaces not before it.
                    // Every space of the line, as in the body, took it and
                    // zh-12db188f's "…於83年7月", whose line weighed them.)
                    // (… and the one before the Latin word that space ends, its
                    // other side: zh-db07d44e's cell "…得基準分80分，" (mode 15,
                    // zh-TW, 12pt) is a line in Word's print, the spaces either
                    // side of "80" set at 2.2 of their 3.0 and "，" at its half.)
                    var wordStart = a
                    while wordStart > 0, units[wordStart - 1] < 0x2E80, !isSpace(units[wordStart - 1]) { wordStart -= 1 }
                    // (Word for Windows: a cell is the body. Lab `csq`, 12pt, the same line in a cell and by a
                    // right indent take the next ideograph at the same width in every one of its rows, digits and
                    // all: two commas 9.75 short with no digit, 7.5 with one (two automatic spaces), 6.0 with three.)
                    var given = topOnly ? [] : legacy || !inCell || RichTextTheme.wordWindowsPages ? spaces + ownSpaces
                        : spaces.filter { $0 == a - 1 || (wordStart < a && $0 == wordStart - 1) }
                    // (A curly quote in a Latin face is as wide as it is.)
                    // (… as it is set: spaced wider, an ideograph 16.6
                    // apart is 8.4 over where its em would be 7.8 over,
                    // and Word leaves it — lab `sq2`.)
                    // (On a character grid the character is its cell, a
                    // grid narrower than the em too: zh-eb54d3b0 (no
                    // compatibility mode, 16pt on a grid of -0.21) takes
                    // "级，" where "级" ends half "升"'s cell past the
                    // margin to the twip, 0.21 short of its em.)
                    // (A full-width quote too: zh-e5eb092a's runs spaced +0.4 set
                    // it 12.8 at 12pt, and its "“市" after "…统一修改为" is left
                    // for the next line in Word's print — the quote 6.8 over,
                    // past half "为"; at its em alone, 6.4, ours took it.)
                    // (An ideograph off the grid is its em and half the spacing
                    // that widens it — the half after it is not over the
                    // margin. zh-01bbcd4d's 16pt, spaced to 17, takes "理。" with
                    // "理" 8.3pt past the margin so, inside half "办"'s 17 (8.8
                    // as spaced); zh-749cb15a's 14pt, spaced to 14.6, leaves
                    // "期" 7.55 past so, over half "長"'s 14.6.)
                    // (Condensed — its run spaced less — it is as wide as it is set: zh-51af781b's
                    // runs spaced -0.75 set "舒适；" 14.5 apart at 16pt, and
                    // Word's print takes "…柔软舒适；" with "适" 6.0pt over by
                    // that, inside half "舒"'s 14.5; counted at its em, 7.5
                    // over, ours sent "适；" down and pages 31-34 ran late.
                    // Not in a cell: zh-cc7a08e8's header "1000米跑（分′秒）"
                    // (mode 11, its bracket run spaced -1 at 14pt) leaves
                    // "秒）" a line down in Word's print, where the set width
                    // took it. Why, not found.)
                    func condensed(_ k: Int) -> Bool {
                        k < runOf.count && (p.runs[runOf[k]].style.letterSpacing ?? lineStyle?.char.letterSpacing ?? _normalChar(document)?.letterSpacing ?? 0) < 0
                    }
                    // (Under `w:kinsoku` 0, before 2013's layout, a closing mark that is a piece of its own
                    // stands over by its half alone, the half that gives: zh-b00fef0d's "…的模式" takes "，"
                    // 12.05 over with four marks, zh-7b125a21's "…车辆安全时" 10.18 at 10.5pt.)
                    let markAlone = RichTextTheme.wordWindowsPages && kinsokuOff && legacy && (!inCell || (document.compatibilityMode ?? 12) < 14) && last == a + 1 && units[a] >= 0x2E80 && Self._closingUnits.contains(units[a])
                    let plain = theme.wordRules && units[a] >= 0x3400 && !Self._closingUnits.contains(units[a]) && !Self._openingUnits.contains(units[a])
                    let lead = Self._closingUnits.contains(units[a]) || Self._openingUnits.contains(units[a]) || units[a] >= 0x2E80 || circled(units[a]) || wideQuote(a)
                        ? (closesUp(a) || markAlone ? em * 0.5 : wideQuote(a) ? em + quoteSpacing(a) / 2 : onCharacterGrid ? boxes(a, a + 1) - (gaps[a] ?? 0) : plain ? (condensed(a) && !inCell ? min(em, boxes(a, a + 1) - (gaps[a] ?? 0)) : em + max(0, boxes(a, a + 1) - (gaps[a] ?? 0) - em) / 2) : max(em, boxes(a, a + 1) - (gaps[a] ?? 0))) : Self._quotes.contains(units[a]) ? boxes(a, a + 1) : w - after
                    // (And where the character before it is over the margin
                    // itself, the paragraph's last mark gives nothing toward
                    // taking the two: the line's other marks must. zh-cfb32050
                    // (mode 14, zh-TW, no list of its own) leaves "額。" after
                    // "…彈性調整得獎名", "額" 7.05pt over, its "、" and "，" able to
                    // give 16 of the 23.05 needed, at their whole 16.4 in Word's
                    // print; ours took it, all three squeezed. Not under
                    // Taiwan's list — `listed`, its rules above: zh-ae3d78ee's
                    // "…你花最多的。" is taken over the margin with a comma giving.)
                    // (Only where that mark is among those giving: where it
                    // gives nothing already — kept — the others' room is
                    // theirs. Lab `s2` (Windows, Word for Windows,
                    // zh-045c5a75's package: mode 14, zh-TW, 標楷體 13pt):
                    // "…直轄市、縣（市）主管機關申請生活扶助。" is one line from
                    // 371pt, "扶" 6 past the margin and "、（）" giving 19 of
                    // their 19.5; ours took the "。"'s half off them again.)
                    let finalGive = centredEnd && paragraphEnd && !listed && p.style.eastAsian["w:overflowPunct"] != "0"
                        && all.contains(tail) && x + min(lead, w) > width + hair ? half(tail) : 0
                    // (Half of a mark as it is set — on a character
                    // grid half of its em and of the grid's addition:
                    // two marks on a grid of 1.008 gave 8.5pt each, a
                    // line 16.9 over at 16pt, zh-457a8d62. A full-width
                    // quote is its glyph and a blank: half its em —
                    // spaced, half its spaced width: lab `p01` (macOS-doc,
                    // Word for Mac, zh-01bbcd4d's package, 16pt spaced to
                    // 17) sets the "“" of "…注记“该权利人…" 8.51 narrower.)
                    // (A closing mark that opens the line gives only the half of its half, from 2013's layout: lab `ldc`
                    // (zh-8628cfbe's cell line "，獲選…1名加2分；合計", Word for Windows) takes "計" 9.0pt over and not 9.2, the "；"
                    // giving 6 and the opening "，" 3; with the comma alone on the line, 3.0 over is taken and 3.2 is not; the
                    // comma as an ideograph, 6.0 and not 6.2. The body agrees: zh-c15af02e's opening "，" is set at 10.2 of
                    // 12.95 in Word's print, and zh-72da925e p8 sends "大" down 8.5pt over where the opening "，" is the only
                    // mark, its quarter em not enough. That replaces the older rule that such a mark gave nothing alone.)
                    func half(_ k: Int) -> Double {
                        // (JIS X 4051's pair table, closing then opening: the closing mark closes up to its half and the
                        // opener after it gives 0.3 em, not its own half. Lab `jis4051` (Word for Windows, compat 15, grid,
                        // 10.5 pt BIZ UDMincho and MS Mincho): "…」「国" and "…）（国" are kept to 8.25 pt over, refused
                        // from 8.5 — the 」 5.25 and the opener about 3.)
                        if noHangJa, k > 0, !legacy, Self._openingUnits.contains(units[k]), Self._closingBracketUnits.contains(units[k - 1]), closesUp(k - 1) {
                            return em * 0.29
                        }
                        let h = wideQuote(k) ? (ems[k] + quoteSpacing(k)) / 2 : (boxes(k, k + 1) - (gaps[k] ?? 0)) / 2
                        return RichTextTheme.wordWindowsPages && !legacy && closingOpeners.contains(k) ? h / 2 : h
                    }
                    let markRoom = all.reduce(0.0) { $0 + half($1) }
                    var room = given.reduce(markRoom) { $0 + (gaps[$1] ?? 0) / 2 }
                    // (Before a digit, from 2013's layout, the automatic space after the piece gives
                    // half of itself besides: lab `dbt` (Word for Windows, zh-db07d44e's p10 cell line
                    // "(1)台電公司經營績效指標（配分權重50％", mode 15) takes "重" 1.34pt past what its
                    // "（" gives and not 1.54 at 12pt, 1.47 and not 1.77 at 14pt, 1.71 and not 2.01 at
                    // 16pt — an eighth of an em each time; with "五十" for the "50", or in mode 14,
                    // only to what the marks give. The label, the cell and the face change nothing.)
                    let digitAfter = RichTextTheme.wordWindowsPages && !legacy && after > 0 && last < units.count
                        && units[last] >= 0x30 && units[last] <= 0x39 && units[last - 1] >= 0x2E80
                    let need = over - hang - after
                    // (In a cell, where the space just before it gives and the
                    // marks cannot give it all, every space of the line gives
                    // the rest — weighed against the line's stretch, as marks
                    // are: zh-d746674a's cell "每年2次(第2、4季)" (mode 15, zh-HK,
                    // YaHei 14pt) is 9.68 over and a line in Word's print, "、"
                    // at its half, 7, and all four spaces 2.8 of 3.5 — 2.68 of
                    // their 7, a share the 9pt stretch over 15.75 allows.)
                    let cellRest: Bool = {
                        guard inCell, !legacy, !topOnly, !RichTextTheme.wordWindowsPages, spaces.contains(a - 1), need > markRoom else { return false }
                        let spaced = (spaces + ownSpaces).reduce(0.0) { $0 + (gaps[$1] ?? 0) }
                        return (need - markRoom) * (gapStretch() + spaced)
                            <= spaced / 2 * (width - x + hair)
                    }()
                    if cellRest {
                        given = spaces + ownSpaces
                        room = given.reduce(markRoom) { $0 + (gaps[$1] ?? 0) / 2 }
                    }
                    // From Word 2013's layout on the test is another:
                    // what each mark must give is no more than the
                    // line would have to stretch by without the
                    // stretch — one mark takes a character half an em
                    // over, two take one two thirds over, three one
                    // three quarters over (measured 2026-10-12).
                    // Measured again 2026-10-13, to a tenth of a point
                    // (labs `mm`, `mm2`, `mm3`): the line is squeezed
                    // where that asks less of it than stretching would
                    // — what the marks must give, as a share of the half
                    // each can give, is no more than what the line
                    // would otherwise stretch by as a share of what it
                    // can stretch: a sixty-fourth of an em at each of
                    // its gaps. So it turns on how many characters the
                    // line holds: with 26 of 16pt, two commas take a
                    // character 11.5 over and not 11.6, seven 14.3 and
                    // not 14.4; with 16 on the line two take 12.9, with
                    // 10, 14.0; at 14pt, 10.0. One mark never gives
                    // more than its half, and every kind of mark gives
                    // alike. Measured on lines of full-width characters
                    // alone; digits and brackets among them are counted
                    // as characters like any (zh-457a8d62 takes a 同
                    // 11.4 over with two marks and 23 characters, which
                    // this allows and a gap fewer would not), and a
                    // line with spaces in it, which stretches at those
                    // first, keeps the older test. So does a character
                    // with a mark after it that hangs: there the marks
                    // may each give no more than the line would stretch
                    // by — one takes it 8.0 over, two 10.4 and not
                    // 10.8, three 11.6 and not 12.0 (lab `mh`), which
                    // is what was first measured.
                    let modern = (document.compatibilityMode ?? 12) >= 15
                    // (Half an em of the character as it is set, its
                    // run's spacing with it: 16pt text spaced -0.4 sets
                    // an ideograph 15.2 apart and takes one 7.55 over,
                    // not 7.65; spaced -1, 6.9 and not 7.1; unspaced,
                    // 7.9 and not 8.1. Lab `sq`, 2026-10-13.)
                    let wide = Self._closingUnits.contains(units[a]) || Self._openingUnits.contains(units[a]) || units[a] >= 0x2E80 || circled(units[a]) || wideQuote(a)
                    // (Without the automatic space after it, which is
                    // no part of the character.)
                    let set = wide && !closesUp(a) ? boxes(a, a + 1) - (gaps[a] ?? 0) : em
                    // (Before 2013's layout the half is the character's
                    // BEFORE it on the line, as that one is set, where it
                    // has one: lab `lq` (Word for Windows, mode 12, 宋体
                    // and Arial 10.5, a "；" on the line to give) takes the
                    // next ideograph up to 5.2pt over after an ideograph,
                    // and after "-" or ")" 1.75 and not 2.0, after "." or
                    // "/" 1.25 and not 1.5, after "W" 4.5 and not 5.0,
                    // after "m" 4.0 and not 4.5, after "i" 1.0 and not 1.5
                    // — half of each; and a "W" after an ideograph 5.0
                    // over, past its own half. zh-1a3c7aa0's cell line
                    // "…苯；2,4-" leaves "二" 4.6 over; zh-1563bd74's
                    // "…能力”" leaves "的" 3.95 over the quote's 3.55.
                    // The automatic space between it and what is taken
                    // goes with the Latin side: lab `lq5`, "…丙3.0" then
                    // "米", is taken 4.0 over and not 4.25 — half of "0"
                    // and its 2.63 of space — and zh-9dd9ce6d's "…层高3.0"
                    // takes "米" 5.75px over; but its "…次年" leaves "3"
                    // 9.75px over, the space and the digit together over
                    // half of "年" alone.)
                    let prior = !opening && a > 0 && !isSpace(units[a - 1]) ? a - 1 : nil
                    let before = prior.map { k in
                        wideQuote(k) ? ems[k] : closesUp(k) ? ems[k] * 0.5
                            : boxes(k, k + 1) - (units[k] >= 0x2E80 || Self._closingUnits.contains(units[k]) || Self._openingUnits.contains(units[k]) ? gaps[k] ?? 0 : 0)
                    } ?? set
                    // (Before 2013's layout a Latin word at the line's end
                    // is taken in a cell whenever the marks and the
                    // automatic spaces can give what it needs — "110.01.01"
                    // 10.5 over, with a full-width colon and two such
                    // spaces on the line, and not 11; an ideograph is taken
                    // half its em over there as in the body. Lab `ovc`,
                    // from zh-4c3793e8's timetable, 2026-10-14. In the body
                    // the word keeps the half-em test: zh-e27cd8bf's "20"
                    // and "2021" are taken by Word, and the body lab `ov`
                    // could not say more — its natural widths were not
                    // known to the point.)
                    // (From 2013's layout too, a Latin word at the line's end
                    // in the body is taken where the marks and automatic
                    // spaces can give what it needs and it starts half the
                    // character before it inside the margin, as before it —
                    // labs `dg` and `ab32`: zh-e0ca7252 (mode 15) takes "15"
                    // in "…於109年6月15" 7.8pt over, its comma and ten spaces
                    // giving 24.5 and "月"'s half inside, and leaves the line
                    // before it its "109", 22.6 of 22.75 and starting 2pt in.)
                    // (One letter or digit, and only that of what is taken
                    // besides its marks: not "②", not a hyphen.)
                    // (A word's own: not a piece of a longer one that a
                    // paragraph without word wrap parts anywhere. zh-0a56c942's
                    // "…目录（2012年）" (wordWrap 0, mode 14, Times 16pt) ends
                    // "（20" in Word's print with "《" and "（" to give 16;
                    // ours took the "1" 7.8 over as a word of its own.)
                    let oneLatin = (a ..< last).filter { !isSpace(units[$0]) && !Self._closingUnits.contains(units[$0]) && !Self._openingUnits.contains(units[$0]) }
                        .map { Self._isLatinWordUnit(units[$0]) ? 1 : 2 } == [1]
                        && !(a > 0 && Self._isLatinWordUnit(units[a - 1]))
                    // (A word of one Latin character from 2013's layout too,
                    // wherever it starts inside the margin, as lab `lw` found
                    // before it: zh-1b74ed91's "…包含建議3項" (mode 15, DFKai-SB
                    // 16pt) ends with "3" starting 1.25pt inside, its two marks
                    // and the spaces round it giving the 6.75. Not with a mark
                    // of its own: zh-15f60bac's "…詳表5第4、6、" leaves "6、"
                    // 18.75 over.)
                    // (On a character grid too, in Word for Windows, the word of one character: zh-c2c92639's
                    // "…不应小于" takes "4" starting 2.3pt inside the margin, its marks and automatic spaces giving 3.2 —
                    // where it starts a quarter of itself inside, no nearer: zh-72da925e's "…(79年" leaves "6" from 1.4.)
                    let latinWord = modern && !wide && !inCell && !lineOther
                        && (!onCharacterGrid ? (x + before / 2 <= width + edge || oneLatin && own.isEmpty && x < width) : RichTextTheme.wordWindowsPages && oneLatin && own.isEmpty && width - x >= (w - after) / 4)
                        && room > 0 && hang == 0 && need <= room + hair
                    let latinBefore = a > 0 && Self._isLatinWordUnit(units[a - 1]) || a > 0 && units[a - 1] == 0x2D
                    // (From 2013's layout a body line with word spaces weighs
                    // them too, at 0.44 of themselves, as a grid's spaces are
                    // weighed. Lab t181 (Windows 01QbbApP, Word for Windows,
                    // zh-505b9619's package: mode 15, 標楷體 14pt, justified,
                    // "…2000立方公尺者，" and four spaces, "小時內單" then "線"):
                    // Word takes "線" up to 4.41pt over, 3.42 with its digits
                    // Han (no automatic spaces), 6.20 without the spaces, 2.74
                    // without the "，"; this gives 4.32, 3.89, 5.93 and 2.56.
                    // The older test — each mark no more than the line would
                    // stretch by — took it 5.15 over. Its corner brackets give
                    // with the rest here: zh-ea70c30e's "…市律師長辦公室 – 投訴"
                    // sets "」" 2.0 narrower in Word's print, with "、", "："
                    // and the spaces round the dash. Not for the paragraph's
                    // last character, no mark after it, which the older test
                    // keeps: zh-84702a67's "填表日期：    年   月   日" takes
                    // "日" with the "：" at its half, twenty spaces whole A closing bracket
                    // ending the paragraph is no such character: zh-33aa9899's
                    // "(五)…須上傳「台灣社區通」" takes "通」" 2.96pt over, its
                    // "」" halved to end on the margin in Word's print.)
                    let wordSpaced = modern && lineOther && !onCharacterGrid && !inCell && !(paragraphEnd && hung == 0 && (!own.contains(tail) || Self._pauseMarks.contains(units[tail])))
                    // (Spaces the line ends with are no stretch if what follows goes down: they go
                    // with it, and what stands before them stretches by that much more.)
                    let windowsSpaced = wordSpaced && RichTextTheme.wordWindowsPages && eastAsianAt(a)
                    let spacedTrail = windowsSpaced ? wordSpaces.filter { sp in sp.k < a && (sp.k + 1 ..< a).allSatisfy { isSpace(units[$0]) } }.reduce(0.0) { $0 + $1.w } : 0
                    func latinBetween(_ k: Int) -> Bool {
                        k > 0 && k + 1 < units.count && Self._isLatinWordUnit(units[k - 1]) && Self._isLatinWordUnit(units[k + 1])
                    }
                    let spacedStretch = !wordSpaced ? 0 : windowsSpaced
                        ? max(0, wordSpaces.filter { spaceWeighs($0.k) }.reduce(0.0) { $0 + $1.w } - spacedTrail) * 0.47
                        // (A Latin piece at the line's end, the spaces between two Latin words weigh less than 0.44 of themselves:
                        // lab `dbw` (Word for Windows, zh-cd8987db's own line, three spaces: two between Latin words, one beside an
                        // ideograph) takes "DB" up to 5.2pt over, where ours stopped at 4.6; with the two Latin spaces removed Word's
                        // limit is 8.6 and ours the same, so the space beside the ideograph keeps 0.44. The 0.2pt steps fix a range:
                        // every weight from 0 to 0.29 reproduces Word's 22 steps, 0.30 gives 21. 0.23 sits inside it.)
                        : wordSpaces.reduce(0.0) { $0 + $1.w * (RichTextTheme.wordWindowsPages && !legacy && !wide && !inCell && !onCharacterGrid && latinBetween($1.k) ? 0.23 : 0.44) }
                    // (From 2013's layout, under `w:kinsoku` 0, a closing mark that is a piece of its own gives
                    // its half and 0.36 of an em by hanging: lab `kq` (mode 15, 16pt, 26 ideographs) keeps
                    // it 11 over with no other mark, 12 with one, 12.5 with two, 13.5 with four; and in Word's
                    // print zh-72da925e's "…的角色" sends "，" down 12.85 over with one.)
                    let kinsokuGive = RichTextTheme.wordWindowsPages && !legacy && kinsokuOff && !inCell && !onCharacterGrid && last == a + 1 && units[a] >= 0x2000 && (Self._closingUnits.contains(units[a]) || (wideQuote(a) && (units[a] == 0x201D || units[a] == 0x2019))) && runRulesOff(a) == false ? em * 0.36 : 0
                    let spacedGive = windowsSpaced ? wordSpaces.filter { spaceGives($0.k) }.reduce(0.0) { $0 + $1.w * spaceGiveShare($1.k) } : 0
                    // (The paragraph's last mark kept from hanging, by the
                    // share test with the automatic spaces weighed at half:
                    // see `squeezedFirst`. zh-d746674a's "…應予以提供。" and
                    // zh-76d361b2's "…代號：F）；" take theirs 22.6 and 24.7
                    // over in Word's print, every mark squeezed and the last
                    // inside the margin; zh-33aa9899's "…不得擅自刪減。" leaves
                    // "減" that stands wholly past it.)
                    // (If a mark and an opening mark part here, the first regains
                    // the blank half it shared with the second. Word's
                    // alternative to compression therefore has that much
                    // less room to stretch: fresh 14pt controls take 甲（
                    // 10pt over, but 「（ only 4pt, not 6, with two commas
                    // on the line, with and without a character grid.
                    // Counting the shared half as spare room took the 『
                    // on zh-72da925e p56 and reflowed its remaining pages.)
                    let partedOpener = macBodyOpener && a > 0 && closesUp(a - 1)
                    // (The automatic space before a Latin word disappears
                    // when that word wraps: it is neither occupied width nor
                    // a stretch opportunity on the alternative line. Fresh
                    // Mac Word controls keep e0ca7252's 第92 with 4.45pt left
                    // before the word, while its date paragraph's 109 still
                    // wraps: the latter has four internal spaces to stretch.
                    // Keep the existing Windows, cell, grid and marked-word
                    // rules; these controls measure plain Mac body words.)
                    // (Word for Windows the same for an ideograph after a digit: lab `csq`, "…5" then "移", two
                    // commas take it 10.75 short where the same with no digit there takes it 9.75, one 9 and not 6.)
                    let macWordGap = modern && !RichTextTheme.wordWindowsPages
                        && !wide && !inCell && !onCharacterGrid && !lineOther
                        && lineWide > 1 && own.isEmpty && a > 0 && Self._isLatinWordUnit(units[a])
                        ? gaps[a - 1] ?? 0
                        : modern && RichTextTheme.wordWindowsPages && wide && !onCharacterGrid && a > 0 && lineWide > 1 ? gaps[a - 1] ?? 0 : 0
                    let stretchRoom = width - x - (partedOpener ? boxes(a - 1, a) - (gaps[a - 1] ?? 0) : 0) + macWordGap
                    // (Plain spaces between two ideographs, in the older layouts, are not counted against the
                    // candidate that follows them: Word's print of zh-bbbb2e6a sets "…拍攝及受  訪" with its two
                    // spaces, the line 1.95pt over before "訪", and takes "訪" 19.95 over by its four marks;
                    // ours counted the spaces in where the candidate starts and sent "訪" down.)
                    var spacesBefore = 0.0
                    if theme.wordRules, RichTextTheme.wordWindowsPages, legacy, !onCharacterGrid, !inCell, wide,
                       a > 0, units[a] >= 0x2E80, units[a - 1] == 0x20 {
                        var k = a
                        while k > 0, units[k - 1] == 0x20 { k -= 1 }
                        if k > 0, units[k - 1] >= 0x2E80 { spacesBefore = boxes(k, a) }
                    }
                    // (A line-end comma hung, a character taken with it: the
                    // share test as well — lab `hc`/`hc3`, Word for Windows,
                    // 標楷體 14pt, justified, compressPunctuation, mode 15,
                    // Latin on the line: 2 inner commas take a character 5.5
                    // short and not 6.5, 1 takes 3.5, 0 takes 1.6, the comma
                    // inside or half hung; zh-6d402586's "…之移" then "工，".
                    // Other marks keep the older test alone: zh-505b9619's
                    // "…為30%）" is taken with its "）" hung.)
                    let commaHangRefused: Bool = {
                        // (Lab `hcg`, the same three lines with "工，", "工；" and "工並": a hung comma and
                        // semicolon alike take 工 1.7, 3.6 and 5.5 short with 0, 1 and 2 inner commas, not
                        // 2.7, 4.6 and 6.5; unhung it is taken 3.7, 6.6 and 7.5 short. So the line's three
                        // automatic spaces weigh about twice themselves against a hung mark. Balance on or
                        // off, the same.)
                        // (Word for Windows any hung mark so: lab `cm2` (zh-c2c92639's "…起吊方法、", mode 15,
                        // 5 marks on the line) with "、，。；：”」）" after "法" refuses the pair at the same width for all eight,
                        // each hung by its half. Not one hung whole: zh-505b9619's "…為30%）" is taken with the "）" a whole
                        // em past the margin, as above.)
                        guard hang > 0, modern, !lineOther, !inCell, !paragraphEnd,
                              units[tail] == 0xFF0C || units[tail] == 0x3001 || units[tail] == 0xFF1B
                                || RichTextTheme.wordWindowsPages && Self._hangingUnits.contains(units[tail]) && hang < em * 0.75 else { return false }
                        guard lineWide > 1, room > 0 else { return true }
                        let gapSum: Double = given.reduce(0.0) { $0 + (gaps[$1] ?? 0) }
                        // (Word for Windows weighs the stretch of the line as it would be with the piece on it: lab
                        // `cm2` (zh-c2c92639's "…起吊方法、", 43 characters and 5 marks before the pair, 10.5pt)
                        // takes "法、" 12.54 over the hang and refuses it at 13.04, as zh-c2c92639's print does,
                        // for every mark after "法"; the line's stretch without the pair allowed 13.54.)
                        var stretch: Double = gapStretch()
                        if RichTextTheme.wordWindowsPages, last > a, last <= ems.count {
                            var pieceEms: Double = 0
                            for k in a ..< last { pieceEms += ems[k] }
                            let n: Int = lineWide + (last - a)
                            stretch = (lineEms + pieceEms) * Double(n - 1) / Double(n) / 64
                        }
                        let capacity: Double = stretch + gapSum * (RichTextTheme.wordWindowsPages ? 2.08 : 1) - macWordGap + spacedStretch
                        return !(need * capacity <= room * (stretchRoom + hair))
                    }()
                    // (Bold spaces after a bold heading, first line, between East Asian text on a justified line, 2010's layout under the balance, give 0.16 of
                    // themselves in Word for Windows' print (one of 0.149 is taken, one of 0.24 is not: zh-5dc5ce34), after the marks: zh-6c447317's "第二十七条  以上…"
                    // sets its two bold spaces 7.05 each on every justified line and 8.03 on the paragraph's last, and so
                    // takes the "保" ours left 0.85pt over; its "第三十八条 一次性…灵活就业" sets "、" at its half and the
                    // one space 6.8 of 8.03, taking "业" 9.2pt over.)
                    var flankedSpaces: [(k: Int, w: Double)] = []
                    if theme.wordRules, RichTextTheme.wordWindowsPages, legacy, p.style.alignment == .justify, document.balancesSpaceWidth,
                       eastAsianAt(a), a > 0, lineFrom < a, !inCell {
                        for k in lineFrom ..< a where units[k] == 0x20 && k < runOf.count && p.runs[runOf[k]].style.bold && k < eastAsianRuns.count && !eastAsianRuns[k]
                            && lineFrom == 0 && k < runOf.count && (0 ..< k).allSatisfy({ units[$0] == 0x20 || p.runs[runOf[$0]].style.bold }) {
                            var l = k - 1, r = k + 1
                            while l >= 0, units[l] == 0x20 { l -= 1 }
                            while r < units.count, units[r] == 0x20 { r += 1 }
                            if l >= 0, r < units.count, units[l] >= 0x2E80, units[r] >= 0x2E80 { flankedSpaces.append((k, boxes(k, k + 1))) }
                        }
                    }
                    let flankedRoom = flankedSpaces.reduce(0.0) { $0 + $1.w * 0.16 }
                    let takenFirst = squeezedFirst && !wordSpaced
                        ? lineWide > 1 && need * (gapStretch() + given.reduce(0.0) { $0 + (gaps[$1] ?? 0) } / 2)
                            <= room * (stretchRoom + hair)
                        : modern
                        ? latinWord || ((!lineOther || wordSpaced) && lineWide > 1 && room + spacedGive + kinsokuGive > 0 && hang == 0
                            // (A sixty-fourth of each gap's em: of the line's
                            // characters as they are sized. zh-84702a67 sets
                            // twenty of a 16pt line's 33 at 10.5pt, and Word
                            // takes "“建" 18.2 over with four marks giving
                            // 26.5 — over by the 16pt sum, under by theirs.)
                            // (And the line's automatic spaces, whole: it would
                            // stretch at those too. Lab `dg6` (Word 16, mode 15,
                            // SimSun 16pt, justified): lines of ideographs and
                            // digit runs, each boundary a 4pt space, take the
                            // next ideograph 9.0pt over with two commas and four
                            // spaces and not 9.5, 10.0 and not 10.5 with two
                            // spaces, 10.5 and not 11 with four commas, 7.5 and
                            // not 8 with eight spaces, 4.5 and not 5 with no
                            // mark at all — each space giving half of itself;
                            // ours took them all to 13. On a character grid the
                            // digits carry the grid's room and no such space.)
                            // (On a character grid the spaces give nothing — Word
                            // sets them whole while the marks give — and weigh
                            // 0.44 of themselves: labs `ab3c`/`ab3a`/`ab3b` (Mac,
                            // Word 16, zh-3c055c9b's line on its 17pt grid) put
                            // Word's limit at ours to the twip with no digits on
                            // the line, 4.45pt past it with ten spaces and 3.95
                            // with fourteen; the line's p2 "頁】，" is taken and
                            // p8's "餐，" (two marks, seven spaces) is not.)
                            ? (onCharacterGrid
                                // (Not the automatic space between the line and what
                                // comes next: sent down, the line ends before it and
                                // has none there to stretch. Lab gs2 (Word for
                                // Windows, zh-3c055c9b's lines alone, w:right stepped):
                                // "…【附件12，第257" takes "頁】，" 39.9 over, every mark
                                // at its half and the spaces 1.6 each, where its two
                                // spaces left would stretch 5.6 each; refused, the
                                // line's three spaces counted, ours sent it down —
                                // and "…第4829號、" the same.)
                                // (Its word spaces weigh too: zh-c2c92639's "…拆除现场" leaves "噪" 6.35 over with
                                // two spaces of 5.5 and two marks, Word for Windows.)
                                ? need * (gapStretch() + given.reduce(0.0) { $0 + ($1 == a - 1 ? 0 : gaps[$1] ?? 0) } * 0.44
                                          + (RichTextTheme.wordWindowsPages && eastAsianAt(a) ? wordSpaces.reduce(0.0) { $0 + $1.w } * 0.47 : 0))
                                    <= markRoom * (stretchRoom + hair)
                                : need * (gapStretch() + given.reduce(0.0) { $0 + (gaps[$1] ?? 0) } - macWordGap + spacedStretch)
                                    <= (room + spacedGive + kinsokuGive) * (stretchRoom + spacedTrail + hair)
                                        * (RichTextTheme.wordWindowsPages && inCell && !legacy && !given.isEmpty ? 1.03 : 1) || cellRest
                                    // (In a cell, a line with automatic spaces as well as
                                    // marks gets 3% more, Word for Windows. Labs cend/cend2
                                    // (the cells alone, w:right stepped): zh-073c9234's
                                    // "…精" takes "進" at a share of 1.047 and
                                    // zh-12db188f's "…函" takes "釋" at 1.046, while
                                    // zh-073c9234's "…擴" refuses "充" at 1.057. Every row
                                    // of all three matches from 1.025 to 1.0375.)
                                    // (A digit that ends a cell's line, Word for Windows: lab
                                    // `sqc`'s "11" is taken 4.5 over and left from 6, half
                                    // its "月", whatever the share test says of the line's
                                    // stretch — zh-8628cfbe's "…員工1" (name 名 down) is
                                    // taken 4.3 over with its "。" squeezed 4.6.)
                                    || (RichTextTheme.wordWindowsPages && !wide && inCell && oneLatin && x < width
                                        && need <= room + hair && x + min(lead, w) - width <= before / 2 + edge))
                            // (To the limit with one mark — 8.0 over is
                            // taken — and short of it with more: three
                            // leave a character 12.0 over.)
                            // (From 2013's layout, on a line with word spaces,
                            // corner brackets give nothing for an ideograph —
                            // lab `sq-sp` (Word 16, zh-ea70c30e's p2, zh-TW
                            // PMingLiU 12.5pt): "…達 10,000 名的說" leaves "有"
                            // 8.3pt over with three "「」" to give, and takes it
                            // as "…達10,000名…". The line's other marks still
                            // give: zh-5b7ae054's "（Big Data）…（Open Data）加"
                            // and zh-e0ca7252's "（由機關填寫）…完" are taken,
                            // zh-c2c92639's "《》（）" too.)
                            // (Nor, with no mark on the line, by this test: see the
                            // word spaces' below — zh-dc25c47e's "□", 2.9pt over
                            // with 6.1 of stretch before it.)
                            : { let giving = modern && lineOther && wide ? all.filter { !Self._cornerUnits.contains(units[$0]) } : all
                                return (!giving.isEmpty || giving.count == all.count) && !(hang > 0 && all.isEmpty) && !(document.balancesSpaceWidth && eastAsianAt(a) && all.isEmpty && a > 0 && isSpace(units[a - 1]))
                                    && need / Double(max(1, giving.count)) <= stretchRoom + (giving.count > 1 ? -_px(0.02) : hair)
                                    && !commaHangRefused }())
                        // (… on a line with spaces in it — `ovc`'s had 41. On
                        // one without, a Latin word no more than half an em
                        // over, the automatic space after it aside: lab `sqc`
                        // from zh-69bbcc3c (mode 14, a centred 12pt cell
                        // "3月，6月，9月，11月", the cell's width varied),
                        // "11" is taken 4.5pt over and left from 6.0, with
                        // "，", "：" or "、" for the marks alike. A word that
                        // carries a full-width mark of its own keeps the room
                        // test: zh-06c46ba9's "（詳參附錄1）" takes "1）" 9pt
                        // over in Word's print.)
                        // (Not, on a line with spaces, one that starts past the
                        // margin, the automatic space before it already over,
                        // as in the body: zh-51af781b's mode-14 scoring cells
                        // end "…干湿区分离，得" in Word's print and open the next
                        // line "1分；…", where ours took the "1" 9.2pt over,
                        // starting 1.4 past, five marks and three spaces able
                        // to give.)
                        // (In Mac Word the ordinary space must separate the
                        // incoming word. Moving one space from inside either
                        // parenthesis of 7b08's form to elsewhere on the line
                        // still leaves A/AA below; placing it immediately
                        // before A/AA keeps them, at the same natural width.
                        // Spaces elsewhere do not bypass the half-em rule.
                        // The Windows cell path retains its measured rule.)
                        : (!wide && inCell && ((lineBlank && x < width
                            && (RichTextTheme.wordWindowsPages || a > 0 && units[a - 1] == 0x20)) || need < set / 2 - _px(0.25)
                            // (… up to half an em and what its own marks give:
                            // zh-d35cbbdb's cell takes no "1333、" 35pt over,
                            // its six marks able to give 44, where Word's
                            // print leaves it and squeezes nothing.)
                            || ((a ..< last).contains { units[$0] >= 0x2E80 }
                                && need <= set / 2 + (a ..< last).filter { units[$0] >= 0x2E80 }.reduce(0.0) { $0 + half($1) } + hair)))
                            || x - spacesBefore + min(lead, w) - width <= before / 2 + flankedRoom + (legacy ? gridGive ?? edge : edge)
                            // (What the line's opening mark gives at its start (`w:topLinePunct`) moves the line
                            // left of the margin rather than squeezing it, and comes off before the half a character:
                            // zh-053f8706 p29 (mode 14) starts "《中华…" 8pt left of the margin and takes "医" 13.75
                            // over, its "》《" giving the rest.)
                            || ({ () -> Bool in
                                let leadGive = all.filter { leadOpeners[$0] != nil }.reduce(0.0) { $0 + half($1) }
                                return leadGive > 0 && need <= room + hair
                                    && x - spacesBefore + min(lead, w) - width - leadGive <= before / 2 + (legacy ? gridGive ?? edge : edge)
                            }())
                            // (Before 2013's layout a piece of digits is taken by the share test, not by half a
                            // character: lab legsq (Word for Windows, zh-eb54d3b0's mode-12 line, right indent
                            // stepped by 2pt) takes "—5000" with need 30.1 and five marks' 43.4 to give where the line
                            // left would stretch 17.3, not 32.1 with 15.3 — and "至5000" 22.1 / 13.5, not 24.1 /
                            // 11.5: the line's automatic spaces weigh 2.3 of themselves; "—五" keeps the half.)
                            // (Only on a line with automatic spaces, as the lab's: with none, zh-749cb15a's "…2014年11月" leaves
                            // "27" 10.4 over in Word's print, and zh-8186c98d's "（国统字〔2019〕" "122" 16.7.)
                            || (RichTextTheme.wordWindowsPages && legacy && !inCell && !onCharacterGrid && room > 0 && lineWide > 1 && !given.isEmpty
                                && (a ..< last).contains { units[$0] >= 0x30 && units[$0] <= 0x39 }
                                && !(a ..< last).contains { units[$0] >= 0x2E80 && units[$0] != 0x2014 }
                                && need * (gapStretch() + given.reduce(0.0) { $0 + (gaps[$1] ?? 0) } * 2.3) <= room * (stretchRoom + hair))
                            // (Under `w:kinsoku` off, where it does not hang, the
                            // paragraph's last mark gives its blank half besides:
                            // lab `lab7b` k0 (macOS-doc, Word for Mac,
                            // zh-7b125a21's package: mode 14, SimSun 10.5pt)
                            // keeps "…决定。" with the "。" set inside the margin
                            // up to 10.48pt over — half the "定" and half the
                            // "。" — and sends it down alone from there; ours
                            // left it from 5.25.)
                            || (kinsokuOff && hang == 0 && a == tail && endsParagraph && Self._closingUnits.contains(units[a])
                                && x + min(lead, w) - width <= before / 2 + half(a) + edge && need <= room + hair)
                            // (In the body a Latin word is taken wherever the
                            // marks and automatic spaces can give what it
                            // needs, with no half of what stands before it
                            // to keep to. Lab `dg` (Word 16, zh-2a241df1's
                            // package, mode 14, justified 14pt): "…，杭州…举报
                            // 43.5" takes "43.5" 8pt over and not 9 — the
                            // comma's 7 and half the 3.56pt space before the
                            // digits; with no comma on the line not even 2.
                            // Not one that starts past the margin: zh-9dd9ce6d's
                            // "…次年" leaves its "3", the automatic space before
                            // it already over the line, though the line's
                            // comma and spaces could give the 9.75pt. Not on a
                            // character grid, where the digits carry the grid's
                            // room: zh-d68ac84a's "给予50" stays a line down at
                            // 11pt over with 12.8 to give.)
                            // (… and one that starts half the character before it
                            // inside the margin, no nearer: lab `ab32` (Word 16,
                            // zh-32f4ad9f's package, mode 14, 16pt, three marks
                            // on the line), "…令第71" and "…令第711" are taken
                            // while they start 8.0pt or more inside it and not
                            // nearer, "第" 16 wide — its line's "711" started
                            // 6.25 in, and ours took it.)
                            // (Only where brackets are all the line has to give:
                            // with a comma or full stop among its marks the word
                            // is taken wherever they can give for it, as before —
                            // zh-54e91165's "…详见附件1。" sets "1" 5.6pt inside the
                            // margin with "。" and "、" giving 5.3 apiece in Word's
                            // print, where the start rule left it a line down.
                            // On a character grid the start rule holds whatever the
                            // marks, and the word is taken there too: zh-8d6f702e
                            // (mode 12, a grid of -0.21) takes "150" starting 7.9pt
                            // in, half "达", its "；" and four automatic spaces
                            // giving, and leaves "60" starting 3.95 in with three
                            // marks to give.)
                            // (A word of one Latin character whenever it starts
                            // inside the margin; a longer one only by the start
                            // rule, whatever marks the line has to give — labs
                            // `lw`, `lw2`, `lw3`, `lw4` (the Windows box, Word for
                            // Windows, zh-eb54d3b0's package, modes 12 and 14,
                            // 仿宋_GB2312 and Times 16pt justified): "、0.3万元" is
                            // taken from 8pt inside and not at 1-7, with "、" or
                            // "件" before it, mid-paragraph or ending it; "件1。"
                            // and "、1万元" are taken 1-6pt over, "件13。" and
                            // "、1.万元" not. In a cell the same, where the marks
                            // can give what it needs: zh-499adba6's "…同時訂定
                            // 1976年至1985" takes "1985" starting 7.8pt inside,
                            // four marks giving 16.2; the cell lab `sqc`'s "11"
                            // is taken 4.5 over and left at 6, half its "月".)
                            // (After a Latin character — a word parted at its
                            // hyphen — the marks give for it as before: zh-424775e4
                            // ends "（US-led" 0.16pt inside in Word's print.)
                            // (Not a one-character word that carries a closing
                            // bracket of its own that cannot hang: that keeps the
                            // start rule. zh-31d580df's "…說明2、3)" leaves "3)"
                            // starting 0.15pt inside, 17.85 over with four marks
                            // able to give 26.5; zh-06c46ba9's "（詳參附錄1）" takes
                            // "1）" starting 10.7 in, and zh-0513f641's "附件4）"
                            // hangs its bracket and is taken.)
                            // (In a legacy Mac cell the letter itself keeps
                            // the half-character limit, excluding its attached
                            // pause mark: 7b08's A and A、 both wrap at right 0
                            // and -2 twips, and both fit at -5. Replacing an
                            // earlier bracket or the preceding one with a comma
                            // changes neither result. Counting all of A、 as
                            // the lead wrongly rejects 23ee's 2、: its digit
                            // is only 1.7pt over, its comma carried with it.
                            // The whole word must still fit the marks' capacity.)
                            || (!wide && x < width && (!inCell || need <= room + hair)
                                && (oneLatin && (RichTextTheme.wordWindowsPages || !inCell
                                    || x + boxes(a, a + 1) - (gaps[a] ?? 0) - width <= before / 2 + edge)
                                    && (hang > 0 || !own.contains { Self._closingUnits.contains(units[$0]) && !Self._pauseMarks.contains(units[$0]) }) && need <= room + hair || x + before / 2 <= width + edge
                                    || !onCharacterGrid && !inCell && latinBefore && all.contains { Self._pauseMarks.contains(units[$0]) }))
                            // (After a space no half of what stands before
                            // limits it: it is taken wherever the marks can
                            // give what it needs — Taiwan's centred "，。、"
                            // nothing. Lab `sp` (Word 16, zh-06c46ba9's
                            // package, mode 14, justified 14pt): "（drug
                            // abuse）之機制建構，2007 年" takes "年" 14pt over
                            // and not 15, the brackets' halves; as "2007年"
                            // it leaves it from 5 over, the "7"'s half.)
                            || (!opening && a > 0 && isSpace(units[a - 1])
                                && need <= all.filter { !(document.marksCentred && Self._centredUnits.contains(units[$0])) }.reduce(0.0) { $0 + half($1) } + hair)
                    // (A stretch with spaces inside it — a closing mark kept
                    // with what its spaces follow — only where the marks can
                    // give all it needs: zh-f47b8a74's "至", 19 spaces and
                    // "，" are 104pt over with 24.5 to give.)
                    // (On a character grid the line's marks before the piece give
                    // a cell's 0.82 at most, however many: lab tg (windows-1,
                    // zh-3c055c9b's package) — one mark gives its 8 of a 17pt
                    // cell, two or more together 13-14; a closing mark that
                    // ends the piece lifts the cap. zh-72da925e p13 leaves
                    // "「基" 23.5 over with "」，：" before it, which ours took.)
                    // (The cap is the piece's grid cell's 0.855, not its em's 0.823:
                    // lab gcap (Word for Windows, zh-7a16a243's "的公益性、對價性、
                    // 適法性下，可以給予" in its table, mode 15, cells of the size
                    // plus 1.0076) takes "予" with three marks up to 0.843 of a cell
                    // and not 0.867, at 10, 12, 14 and 16pt alike; with two, 0.787.)
                    let gridCapped: Bool = {
                        // (An East Asian piece: a Latin word is taken as before —
                        // zh-72da925e's "…控制站流量5,400cms" with "，「」" giving.)
                        // (Word for Windows': lab tg was printed there, and Mac
                        // mode lost zh-3c055c9b's and zh-c15af02e's lines with it.)
                        // (Nor on a line with Latin words, as tg's had none:
                        // zh-344a8d08's "…Google Analytics…（pageviews）…所附「網"
                        // is taken in Word's print.)
                        guard theme.wordRules, RichTextTheme.wordWindowsPages, onCharacterGrid, !lineLetters, last > a, units[a] >= 0x2E80, !Self._closingUnits.contains(units[last - 1]) else { return false }
                        let before = all.filter { $0 < a }
                        guard before.count >= 2 else { return false }
                        // (A mark right after another gives its whole half beside the cap: zh-3c055c9b p11's
                        // "…寫的。」、「（舉" is taken 34.8pt over in Word's print, "」" and "、" set at 8.4 of a
                        // 17pt cell, "，" and "。" giving 11.7 between them. zh-72da925e's "」，：", none by
                        // another, keep the cap.)
                        let marks = Set(all)
                        let joined = before.filter { $0 > 0 && marks.contains($0 - 1) }
                        let mid = before.filter { !($0 > 0 && marks.contains($0 - 1)) }.reduce(0.0) { $0 + half($1) }
                        let ownRoom = all.filter { $0 >= a }.reduce(0.0) { $0 + half($1) }
                        let cell = boxes(a, a + 1) - (gaps[a] ?? 0)
                        return need > min(mid, 0.855 * cell) + joined.reduce(0.0) { $0 + half($1) } + ownRoom + given.reduce(0.0) { $0 + (gaps[$1] ?? 0) / 2 } + hair
                    }()
                    // (An opening bracket that opens what is being taken, right after a closing mark it closes up
                    // with, gives 0.22 of an em less than its half, in Word for Windows: at 16pt zh-6c447317 takes
                    // "（日" 8.7 over and zh-ec1b6f63 "《就" 12.15 with two marks, where zh-cada2385 leaves "（仙" 13.3
                    // and zh-053f8706 "（永" 13.75; with three, "（GB55" 17.35 and "《义" 16.7 are taken and "（五）"
                    // 20.75 and "（鲁" 21.75 are not. With no other mark, both ways: zh-053f8706 takes "《浙" 5.75 over at p46's
                    // foot and leaves it at another line's end.)
                    let pairedOpener = RichTextTheme.wordWindowsPages && !inCell && !onCharacterGrid && last > a + 1 && a > 0
                        && units[a] >= 0x2E80 && Self._openingUnits.contains(units[a]) && closesUp(a - 1) && legacy
                        && !Self._pauseMarks.contains(units[a - 1])
                        && all.contains(a) && all.count >= 2 && need > room - em * 0.22 + hair
                    // (Nor a multiplication sign squeezed in where another, or a digit, follows it: Word for Windows
                    // takes "×" there only where it fits whole. Lab `lef` (windows, zh-621d8756's "…今天要对××情况",
                    // mode 14, the right indent stepped by 20 twips) takes the first "×" from 0.3pt inside the
                    // margin and not 0.7 over, three marks able to give 21; zh-6b242483's "（家）×1（每年1次）" leaves
                    // its "×" 5.1 over. Six such takes of ours in the 756, none of Word's. After it an ideograph,
                    // the marks give as for any: zh-621d8756's "…请提供×××" keeps its first.)
                    // (Only the FIRST "×" of its run: every take behind the rule opens one. Inside a run Word squeezes to take
                    // it: zh-621d8756's p47 "…违反了《×××××" sets the fifth "×" 0.3pt past the margin, six marks giving
                    // 4.4pt of the 4.7 over, ~0.95 each.)
                    let timesGlued = wordRules && RichTextTheme.wordWindowsPages && last < units.count && units[last - 1] == 0xD7
                        && (a == 0 || units[a - 1] != 0xD7)
                        && (units[last] == 0xD7 || (units[last] >= 0x30 && units[last] <= 0x39))
                    // (Nor a Latin word that opens on a letter and is longer than one, on a grid, taken by
                    // the squeeze: lab `latg` (Word for Windows): a line of 26 ideographs and "R6", "R6B1"
                    // or "R" is left at the margin whatever room the line's marks have to give, and "B1" is
                    // set only where its natural width fits; zh-08e95de4's "…西站片区R6地块" ends at "区",
                    // 9.7pt over with two marks to give 16, where ours took it. Only one that starts less than a cell
                    // inside the margin (R6: 9.0): zh-7654804a's "PCM" (starts 30 in), zh-344a8d08's "COVID-" (46)
                    // and zh-3c055c9b's "PChome" (37) are taken by the squeeze.)
                    let letterWord = wordRules && RichTextTheme.wordWindowsPages && onCharacterGrid && last - a >= 2
                        && ((units[a] | 0x20) >= 0x61 && (units[a] | 0x20) <= 0x7A) && units[a] < 0x80
                        && (a ..< last).allSatisfy { units[$0] < 0x2E80 && !isSpace(units[$0]) } && x + w > width + hair
                        && w - need < before - hair && need <= room + hair
                    if Self.debugFitLog, letterWord, takenFirst {
                        let pt = theme.pixelsPerPoint * scale
                        FileHandle.standardError.write(Data("LETTERWORD\t\(String(decoding: units[a ..< last], as: UTF16.self))\tx \(x / pt)\tw \(w / pt)\twidth \(width / pt)\tneed \(need / pt)\troom \(room / pt)\tbefore \(before / pt)\tmarks \(all.count)\tprev \(String(decoding: units[max(0, a - 3) ..< a], as: UTF16.self))\tnext \(String(decoding: units[last ..< min(units.count, last + 2)], as: UTF16.self))\n".utf8))
                    }
                    // (Nor a digit squeezed in where an em dash follows it: lab `e68` (windows, zh-e68a2f57's "…间距按表4—1控制。",
                    // mode 14, the right indent stepped by 0.2pt) takes the "4" while it fits and sends it down from 0.2pt over,
                    // though the same line with an ideograph after the "4" takes it through 5pt over, one mark giving; with a second
                    // mark earlier on the line (a "，") the same. The break between the digit and the dash is allowed
                    // where the digit fits (zh-e68a2f57 p14's "按表5|—1规", zh-8d6f702e's "达100|—150"). Only a lone digit: Word squeezes
                    // in a number of several digits and a Latin run before the dash — zh-8d6f702e's and zh-c2f6d17a's "…雨量达150|—200 毫米"
                    // (mode 12, a character grid, need 15.8) and zh-4a2ab598's "T/CAS677|—2022" (mode 14, no grid, need 0.9) are taken.)
                    let dashGlued = wordRules && RichTextTheme.wordWindowsPages && last < units.count && units[last] == 0x2014
                        && units[last - 1] >= 0x30 && units[last - 1] <= 0x39 && need > hair && last - a == 1
                    let taken = takenFirst && !gridCapped && !pairedOpener && !timesGlued && !dashGlued && !letterWord && !(legacy && (a ..< last).contains { units[$0] == 0x20 } && Self._closingUnits.contains(units[last - 1]) && need > room + hair)
                        // (Word for Windows, old format: it takes a character up to about 0.017pt past half an em and refuses from 0.019:
                        // zh-d950cedb's "配" 8.02 over 8.0, zh-015abfaf's 7.897 over 7.874; the 15 takes in 3 documents are at most 0.016; not one that ends on a closing mark: zh-16e0a12a's "门)" is taken.)
                        && !(legacy && wide && !Self._closingUnits.contains(units[last - 1]) && RichTextTheme.wordWindowsPages && over > before / 2 + _px(0.017) && over <= before / 2 + _px(0.03))
                    if Self.debugFitLog {
                        let pt = theme.pixelsPerPoint * scale
                        let gapSum = given.reduce(0.0) { $0 + (gaps[$1] ?? 0) }
                        let wsSum = wordSpaces.reduce(0.0) { $0 + $1.w }
                        let flags = "\(modern ? 1 : 0)\t\(legacy ? 1 : 0)\t\(wide ? 1 : 0)\t\(lineOther ? 1 : 0)\t\(wordSpaced ? 1 : 0)\t\(squeezedFirst ? 1 : 0)\t\(paragraphEnd ? 1 : 0)\t\(latinWord ? 1 : 0)\t\(oneLatin ? 1 : 0)\t\(gridCapped ? 1 : 0)\t\(kept ? 1 : 0)\t\(commaHangRefused ? 1 : 0)"
                        FileHandle.standardError.write(Data("FITQ\t\(i)\t\(a)\t\(over / pt)\t\(hung / pt)\t\(hang / pt)\t\(need / pt)\t\(room / pt)\t\(markRoom / pt)\t\(all.count)\t\(given.count)\t\(gapSum / pt)\t\(wordSpaces.count)\t\(wsSum / pt)\t\(stretchRoom / pt)\t\(lead / pt)\t\(set / pt)\t\(before / pt)\t\(em / pt)\t\(finalGive / pt)\t\(takenFirst ? 1 : 0)\t\(taken ? 1 : 0)\t\(flags)\n".utf8))
                    }
                    if traced {
                        let pt = theme.pixelsPerPoint * scale
                        FileHandle.standardError.write(Data("    over \(over / pt) hang \(hang / pt) need \(need / pt) room \(room / pt) of \(all.count) marks, lead \(lead / pt) set \(set / pt) taken \(taken) — \(lineWide) characters of \(lineEms / pt) ems, \(given.count) spaces, other \(lineOther)\n".utf8))
                    }
                    // (A Latin word's own curly quotes give nothing for it
                    // in the body: lab `sq-q` (zh-b00fef0d's package,
                    // mode 12, kinsoku off, 16pt) sends all of "“1”" down
                    // with 32pt of room from four marks, two of them its
                    // own quotes, and takes "1" alone; zh-b00fef0d's p5 took
                    // the word 29.4 over.)
                    // (Its own curly quotes, before 2013's layout: other
                    // marks of its own still give — zh-6b242483, zh-38d26944
                    // and eight more fell when every one of them stopped.)
                    let ownGive = !inCell && legacy && (a ..< last).contains { (units[$0] >= 0x30 && units[$0] <= 0x39) || (units[$0] >= 0x41 && units[$0] <= 0x7A) }
                        ? own.filter { [0x201C, 0x201D, 0x2018, 0x2019].contains(units[$0]) }.reduce(0.0) { $0 + half($1) } : 0
                    // (No squeeze in the body takes a circled number:
                    // zh-30d86fcf's line "…条件：" leaves its colon a full em
                    // in Word's print and opens the next with "①", where ours
                    // set the colon at 13.5 of 16 to take it. In a cell one
                    // does: zh-20ff844e's narrow cells take their "③".)
                    // (Not for Word for Windows, where the half-character rule does it: a circled number counts as wide, so
                    // zh-30d86fcf's "…条件：①" (8.7 over, half an em 8) stays refused and its "…申请条件。③" (0.7 over, the "。"
                    // set 15.72) is taken.)
                    let circled = !inCell && !RichTextTheme.wordWindowsPages && a < units.count && (0x2460 ... 0x24FF).contains(units[a])
                    if room + spacedGive + kinsokuGive + flankedRoom > 0 || digitAfter, taken, !circled, need <= room + spacedGive + kinsokuGive + flankedRoom - ownGive - finalGive + (gridGive ?? hair) + (digitAfter ? after / 2 : 0) {
                        let share = room > 0 ? min(1, (need + 0.02) / room) : 0
                        // (The marks give first, and the automatic spaces
                        // what is still needed: the colon of lab `ovc` is
                        // set at its half, 7.0, and the two spaces at 2.63
                        // of their 3.5, not all three at a share.)
                        let markShare = given.isEmpty || markRoom <= 0 ? share : min(1, (need + 0.02) / markRoom)
                        let spaceShare = given.isEmpty || markRoom <= 0 ? share
                            : min(1, max(0, need + 0.02 - markRoom) / max(0.001, room - markRoom))
                        for mark in all { adjust[mark, default: 0] -= half(mark) * markShare }
                        for mark in all where leadOpeners[mark] != nil { leadOpeners[mark] = last }
                        for k in given { adjust[k, default: 0] -= (gaps[k] ?? 0) / 2 * spaceShare }
                        // (What the marks cannot give of that fiftieth —
                        // where they give all they have — the last
                        // character does: the engine allows the line
                        // nothing over.)
                        var short = need + 0.02 - room * share
                        if short > 0.001, spacedGive > 0 {
                            let spaceDraw = min(1, short / spacedGive)
                            for space in wordSpaces where spaceGives(space.k) { adjust[space.k, default: 0] -= space.w * spaceGiveShare(space.k) * spaceDraw }
                            short -= spacedGive * spaceDraw
                        }
                        if short > 0.001, flankedRoom > 0 {
                            RuleTrace.hit("word-justified-bold-spaces-between-ideographs-give-a-sixth-in-2010s-layout")
                            let draw = min(1, short / flankedRoom)
                            for sp in flankedSpaces { adjust[sp.k, default: 0] -= sp.w * 0.16 * draw }
                            short -= flankedRoom * draw
                        }
                        // (Before a digit, what the marks cannot give the line's ideographs do, a
                        // hundredth of an em or so each: lab `dbs`'s print sets "（" 5.88 and the
                        // ideographs 11.88 and 12.00 to take "重" 1.34 past the "（"'s half.)
                        let wides = digitAfter ? (lineFrom ..< last).filter { units[$0] >= 0x3400 && !all.contains($0) } : []
                        if short > 0.001, !wides.isEmpty {
                            for k in wides { adjust[k, default: 0] -= short / Double(wides.count) }
                        } else if short > 0.001 { adjust[last - 1, default: 0] -= short }
                        if hang > 0 { adjust[tail, default: 0] -= hang }
                        if after > 0 { adjust[tail, default: 0] -= after }
                        fits = true
                    }
                }
                // (Under `balanceSingleByteDoubleByteWidth` word spaces give
                // nothing for East Asian text that follows them: zh-dc25c47e's cell "…□广播电视
                // □纸质媒体" (mode 15, justified, 9pt 仿宋_GB2312) leaves its "□"
                // 2.9pt over in Word for Windows' print, six spaces of 4.5 on
                // the line — and "甲", "（" or "※" there alike (lab dcs); ours
                // set them at 4.02 to take it. They give for what is inside a
                // word: zh-604e21e5's "…(Backup & Restore)的標準程", 5.88 of 6.
                // Without the balance they give after a space too: zh-f2ca3070's
                // "…共同工作空間   席", 4.80 of 6. A Latin word after them keeps
                // lab `jg`'s rule: zh-4b8e0abc's Indonesian, balanced, mode 15.)
                if !fits, !opening, squeezesSpaces || pageBox,
                   !(document.balancesSpaceWidth && eastAsianAt(a) && a > 0 && isSpace(units[a - 1])),
                   // (Korean, balanceSingleByteDoubleByteWidth, in a table cell: Word stretches, never squeezes, a space to take a Hangul syllable (15093019); in body text it squeezes, 107500a8 takes '기' at 0.46 em spaces.)
                   !(RichTextTheme.wordWindowsPages && document.balancesSpaceWidth && (inCell || !legacy && p.style.eastAsian["w:wordWrap"] == "0" && isSpace(units[a])) && units[a ..< last].first(where: { !isSpace($0) }).map({ $0 >= 0xAC00 && $0 <= 0xD7A3 }) == true && !(legacy == false && a + 2 >= units.count && p.style.eastAsian["w:wordWrap"] == "0")),
                   // (And with wordWrap ON in a compat-15 cell Word never squeezes to take a last word that holds Hangul, even one that opens on a digit: lab ko-stop3 ww and leftww, tcW 7760-7960, 101 cases, never taken; 6건입니다.)
                   !(RichTextTheme.wordWindowsPages && document.balancesSpaceWidth && inCell && !legacy && p.style.eastAsian["w:wordWrap"] != "0" && Self._koreanLastWord(units, a)),
                   !wordSpaces.isEmpty || (!(spaces + ownSpaces).isEmpty && units[a] != 0xFFFC && !isSpace(units[a])) {
                    // (Less what its last mark hangs.)
                    var need = x + w - after - width - hang
                    // (Right to left, an Arabic word is placed in pieces; the squeeze weighs the whole
                    // word, and takes its other pieces with it: kash2 lab, docs/plans/kashida.md.)
                    var restPieces = 0
                    let indicPiece = RichTextTheme.wordWindowsPages && !legacy && a > 0 && !isSpace(units[a - 1]) && Self._isIndic(UInt32(units[a]))
                    let georgianPiece = RichTextTheme.wordWindowsPages && !legacy && a > 0 && !isSpace(units[a - 1]) && units[a] >= 0x10A0 && units[a] <= 0x10FF
                    // (A Georgian word is placed in pieces too (only the stretch is measured from the word's start; the piece totals stay as they were): xs 1a285b32's justified Sylfaen line takes "მგრძნობელობა" 2.7 pt over with nine spaces in Word; measured from its last letter the stretch looked 2 pt and the test refused it.)
                    if RichTextTheme.wordWindowsPages, p.style.rightToLeft || indicPiece, !legacy, !piece.hard, piece.last == piece.b {
                        var q = pieceIndex
                        // (An Indic word's closing danda is the paragraph's last piece, and the squeeze takes it with the word: dx2 ne 9baed400's "भएको।" is one line in Word's print, its spaces at the quarter cap, ours left "भएको।" for the next.)
                        while q + 1 < pieces.count, pieces[q].last == pieces[q].b, !pieces[q].hard, pieces[q + 1].a == pieces[q].b,
                              !pieces[q + 1].hard || (indicPiece && units[pieces[q + 1].a] >= 0x964 && units[pieces[q + 1].a] <= 0x965) {
                            q += 1; need += pieces[q].w; restPieces += 1
                        }
                    }
                    // (The automatic spaces between ideographs and Latin
                    // give too, half of themselves at most: zh-b13d0fb4's
                    // "家新創品牌Startup Island TAIWAN，提升臺灣國際能見度。"
                    // (mode 15, justified, a cell) is one line in Word's
                    // print, 2.46pt over, its two spaces set at 2.3 of
                    // 3.12 and the space after "牌" at 1.8 of 3.0 — ours
                    // gave the spaces only and left "度。" for the next.)
                    // (… with no word space on the line as well: zh-c5f59397's
                    // "期程自112年度至114年度，113年度…貨櫃", its five spaces
                    // between ideographs and digits set at 2.7 of 3.0 in
                    // Word's print, takes "櫃" 1.16pt over. Half of each, and a
                    // quarter of an em in all: zh-adfe24a7's "…善用GIS、…計畫
                    // 執行" leaves "行" 2.88pt over with its one, and the same
                    // document's "…3艘35噸級巡緝艇及3艘5噸級快艇，113年度預定
                    // 辦" takes no "理" with eight.)
                    let autos = spaces + ownSpaces
                    // (… half an em in all for what ends with a closing mark,
                    // which no line may start with: zh-7cf85f15's cell line
                    // "五、辦理112年與113年總資源…經濟預測。" (mode 15,
                    // justified, PMingLiU 12) takes "測。" 5.24pt over with
                    // four, each set at 1.62 of 3.0 in Word's print, where
                    // zh-c5f59397's "…噸級巡" leaves a plain "緝" 3.8 over.)
                    let closes = last > a && Self._closingUnits.contains(units[last - 1])
                    // (And for what opens with an opening mark, which no line
                    // may end with: zh-4ea36aa8's cell line "二、校舍…國小部32班（含"
                    // (mode 15, doNotCompress, justified, PMingLiU 12) takes
                    // "（含" 5.7pt over with four, each set at 1.58 of 3.0 in
                    // Word's print, where ours left "（含" for the next line.)
                    let opens = last > a + 1 && Self._openingUnits.contains(units[a])
                    // (A quarter, not half, where the closing mark hangs, and
                    // nothing by the share test with no mark to give: zh-6d402586's
                    // "…(以下稱1人1室房" leaves "間)：" 5.4pt over past its hung
                    // "：" with eight automatic spaces; zh-1b74ed91's "…作業，"
                    // is taken 1.0 over with three.)
                    // (0.47 of itself in Word for Windows: lab `sq`'s 2.2 of 2.5 with two at 10pt is taken and
                    // 3.0 with six is not; zh-64c27df5's cell "…標準大" leaves "氣" 1.42 over with one of 3.0,
                    // zh-4ea36aa8's "…國小至" "高" 2.96 with three, where zh-4f883dce's 2.44 with two is taken.)
                    let cellWindows = RichTextTheme.wordWindowsPages && inCell && !legacy && !onCharacterGrid && hang == 0
                    // (In a cell, 0.54: lab `cend` (Word for Windows, zh-147bdae0's p60 cell, 標楷體 12, mode 15) takes
                    // "程" with one automatic space of 3.0 and no word space 1.51pt over and not 1.76, and with the
                    // line's word space of 6.0 3.01 and not 3.26 — the word space its quarter; zh-64c27df5's cell
                    // leaves "氣" 1.73 over with one, at Word's own width.)
                    let autoGive = cellWindows ? 0.54 : RichTextTheme.wordWindowsPages ? 0.47 : 0.5
                    // (From 2013's layout a quarter of each, where that is more than the quarter em: lab `asp`
                    // (Word for Windows, zh-147bdae0's p64 line "地之檢討，102年11月29日已頒訂「都市計畫公共設施保",
                    // mode 15, doNotCompress, 標楷體 12, a cell or the body, no grid) takes "保" with five spaces of 3.0
                    // 3.4pt over and not 3.8, with four 2.7 and not 3.1 — the digits' face and the "「" alike.)
                    let quarterEach = RichTextTheme.wordWindowsPages && !legacy && !onCharacterGrid && hang == 0 ? autos.reduce(0.0) { $0 + (gaps[$1] ?? 0) } / 4 : 0
                    // (In a cell, Word for Windows from 2013's layout, no quarter em for an ideograph — the share
                    // test below limits it — and half an em for a Latin word: at Word's own cell widths
                    // zh-147bdae0's "…截至109年8月" takes "月" 3.25pt over with four of 3.0 and its "…公共設施保"
                    // "保" 3.47 with five, and zh-4ea36aa8's "…為了加強臺灣IC" "IC" 3.15 with three, where its
                    // "…國小至" leaves "高" 3.26 over by the share; zh-8628cfbe's "…每退步1名減" leaves "1" 7.0.)
                    let autoCap: Double = cellWindows && eastAsianAt(a) ? .infinity
                        : max(quarterEach, (closes && hang == 0) || opens || (cellWindows && units[a] < 0x2E80) ? em / 2 : em / 4)
                    let roomAutos = min(autos.reduce(0.0) { $0 + (gaps[$1] ?? 0) } * autoGive, autoCap)
                    // (A word space beside East Asian text gives a fifth of
                    // itself, not a quarter, in Word for Windows' print:
                    // zh-b5359de4's "…宜选用 LED 灯或…控制方式；" (mode 15,
                    // justified, 12pt 宋体) wraps "式；", the two spaces
                    // needing 1.38 of 6 each; zh-f2ca3070's three, 1.2.
                    // Between Latin words, lab `jg`'s quarter stands, and so
                    // does it after a circled number: zh-1d2a7c35's
                    // "① 計畫內容…" (a space in the text, not the label's
                    // suffix) keeps 之 on its line in Word's print.)
                    // (A space beside HANGUL gives the full quarter in a body paragraph: lab kofit-mix-malgun,
                    // Malgun 11pt, 13 right-indent steps, Word keeps "Korea" at the line end through step 6
                    // where a fifth refused it at step 2. Hanja/kana neighbours keep the fifth.)
                    func zhNeighbour(_ i: Int) -> Bool {
                        eastAsianAt(i) && !(!inCell && (0xAC00...0xD7A3).contains(units[i]))
                    }
                    func spaceGive(_ k: Int) -> Double {
                        pageBox ? 0.4 : balancedLatinSqueeze ? 0.5 : RichTextTheme.wordWindowsPages && !(k > 0 && (0x2460...0x24FF).contains(units[k - 1])) && ((k > 0 && zhNeighbour(k - 1)) || (k + 1 < units.count && zhNeighbour(k + 1))) ? 0.2 : 0.25
                    }
                    let windowsAfterMarks = RichTextTheme.wordWindowsPages && eastAsianAt(a) && !inCell
                    // (A space of a missing Hangul-named face is Yu Gothic's: 0.5 em wide beside Hangul, but only Yu's own advance
                    // (584/2048 em) gives a quarter when the line is squeezed; xb kor 22de7d, whose "1. 초록" line Word breaks
                    // before "(Zero-" where the full 5 pt per space gave 16 pt of room.)
                    func giveBase(_ s: (k: Int, w: Double)) -> Double {
                        guard document.balancesSpaceWidth, theme.wordRules, RichTextTheme.wordWindowsPages, !document.hasIndicText,
                              s.k < runOf.count, s.k > 0, s.k + 1 < units.count,
                              (0xAC00...0xD7A3).contains(units[s.k - 1]) || (0xAC00...0xD7A3).contains(units[s.k + 1]),
                              _yuLatinOfMissingHangulFace(p.runs[runOf[s.k]].style, lineStyle, document) else { return s.w }
                        RuleTrace.hit("word-missing-hangul-face-space-gives-yu-advance")
                        return min(s.w, em * 584.0 / 2048)
                    }
                    let givers = windowsAfterMarks ? wordSpaces.filter { spaceGives($0.k) } : wordSpaces
                    // (A number or Latin word brought onto a body line, Word for Windows, no grid: the automatic
                    // spaces give a quarter em and 0.3 of themselves, and a word space nothing. Lab `ds`
                    // (zh-eccb2003's "…資訊公開從105", mode 15, doNotCompress, 14pt) takes "105" 6.2pt over and not
                    // 6.7 with three spaces of 9.8, 8.0 and not 8.5 with five of 16.1, and with "2025 年"'s word
                    // space for an automatic one 5.4 and not 5.9.)
                    let latinPulled = RichTextTheme.wordWindowsPages && !inCell && !legacy && !onCharacterGrid && hang == 0
                        && !pageBox && units[a] < 0x2E80 && !circled(units[a]) && !autos.isEmpty
                    // (Word for Windows, a line of Latin words between ideographs: past a quarter of each space
                    // the marks and ideographs AFTER the last word space give too, a sixty-fourth em each, the
                    // head before the Latin none. Lab `squeeze` (zh-25381d22, 12pt, "（Proof of Concept, PoC），…市約"):
                    // takes "約" with 3.74 of need at right indent +0.5, not 4.24 at +1.0, the spaces' quarters
                    // 2.34; its print has the tail's glyphs 0.12 short and the head's whole.)
                    // Only when the last space has ASCII letters/digits/commas on both sides (a real Latin word
                    // run); a space after a curly quote beside ideographs (zh-cd48112c) gave 9 pt of false room.
                    let latinLastSpace: Bool = !wordSpaces.isEmpty && wordSpaces.last!.k >= 1 && wordSpaces.last!.k + 1 < units.count
                        && Self._asciiWordUnit(units[wordSpaces.last!.k - 1]) && Self._asciiWordUnit(units[wordSpaces.last!.k + 1])
                    let tailSqueezers: [Int] = windowsAfterMarks && !latinPulled && latinLastSpace && wordSpaces.count >= 3 && !givers.isEmpty  // 3+ spaces: lab had 3 (took need 3.74); zh-15f60bac (2 spaces, need 4.45) and zh-604e21e5 (1 space, need 1.89) refuse
                        ? Array(((wordSpaces.last!.k + 1) ..< a).filter { units[$0] >= 0x2E80 && eastAsianAt($0) }.prefix(8)) : []  // at most 8 (lab: 8 gave 1.5; zh-79d08edd, 12 after one space, refused at 0.78+2.25)
                    let tailRoom: Double = Double(tailSqueezers.count) * em / 64
                    let roomSpaces = latinPulled ? em / 4 + autos.reduce(0.0) { $0 + (gaps[$1] ?? 0) } * 0.3
                        : givers.reduce(0.0) { $0 + giveBase($1) * (windowsAfterMarks ? 0.25 : spaceGive($1.k)) } + roomAutos + tailRoom
                    // (And only where each space gives at most half of
                    // what each would stretch were the word left for the
                    // next line: lab `jg` (Word for Windows, Times New
                    // Roman 12, a last word of 3 to 28pt after 8 and 16
                    // spaces) takes "x" 3.1pt over and "mmm" 10.7 —
                    // to a tenth of a point, as are lab `jt`'s lines of
                    // "ab" and "abcd". bug65649's Cyrillic took a word
                    // Word leaves, or left one it takes, line after line.)
                    // (Right to left, an Arabic word is placed in pieces, split after the letters that
                    // do not join forward; the stretch is measured from where the word's text starts,
                    // not from its last piece (kash2 lab, docs/plans/kashida.md). And lowKashida
                    // stretches at kashida too: each joined pair on the line counts 3.1 spaces.)
                    let arabicLine = RichTextTheme.wordWindowsPages && p.style.rightToLeft && !legacy
                    // (A Hangul word kept whole (hangul-word-held-whole) is placed in pieces too: the stretch is
                    // measured from where the word starts, as for Arabic; 59e77f's "'구조적" is taken by Word
                    // with its spaces at 1.8 pt of 2.49.)
                    let hangulPiece = RichTextTheme.wordWindowsPages && !legacy && p.style.eastAsian["w:wordWrap"] != "0"
                        && units[a] >= 0xAC00 && units[a] <= 0xD7A3
                    // (An Indic word is placed in pieces too, so a piece inside a word measures from where the word starts: kok15/kok14 lab, a justified Kokila line
                    // takes its 18th word 10 pt over with 17 spaces; measured from the piece, the stretch looked 6 pt and the test refused it.)
                    let stretch = width - ((arabicLine || hangulPiece || indicPiece || georgianPiece) && !wordSpaces.isEmpty ? spaceBaseX : x - (wordSpaces.last?.w ?? 0))
                    let lowJoins = arabicLine && p.style.eastAsian["w:jc"] == "lowKashida" && !wordSpaces.isEmpty
                        ? 3.1 * Double(ArabicForms.joins(units[lineFrom ..< max(piece.b, wordSpaces.last?.k ?? lineFrom)].map { UInt32($0) }[...])) : 0
                    let halfStretch = wordSpaces.count < 2 || balancedLatinSqueeze  // (a left-aligned line has no stretch to weigh: oxsdk-1c09b12993's notes)
                        || need / Double(wordSpaces.count) <= stretch / (Double(wordSpaces.count - 1) + lowJoins) / 2 + hair
                    // (Where automatic spaces give, off a character grid,
                    // they give as marks do from 2013's layout: what the
                    // spaces must give, as a share of what they can, is no
                    // more than the line would stretch by, as a share of a
                    // sixty-fourth of each gap's em and the spaces whole.
                    // Lab `as` (Mac, Word 16, zh-5bfac68f's package: mode 15,
                    // zh-TW, PMingLiU 12, justified, compressing nothing):
                    // "甲…i…甲乙", two automatic spaces of 3.0, takes "乙"
                    // 2.0pt over and not 2.5; with "i" and "a", four, 2.5 and
                    // not 3.0; with none, nothing over. zh-5bfac68f's
                    // "…型態i僑卡…基礎，並" leaves "並" 2.83 over so, where half
                    // of each — 3.0 — took it; and its cell's "…（i-Taiwan
                    // Window）服務，提供年輕人返臺" a "投" 2.91 over, a word
                    // space among them. An ideograph's test: a Latin word
                    // is taken where they can give it — zh-4ea36aa8's cell
                    // "…為了加強臺灣IC" ends so in Word's print.)
                    let autoRoom = autos.reduce(0.0) { $0 + (gaps[$1] ?? 0) }
                    // (In a cell, Word for Windows, 0.52 where each gives no more than the quarter em: at Word's
                    // cell widths zh-301618c5's and zh-4f883dce's "…法規彙編」等" take "刊" 2.74 over with two
                    // of 3.0, 0.50 and 0.52 of them by this test, and zh-147bdae0's "…所需之輔助介" "面" 2.70 at
                    // 0.517, where its "…通盤檢討前" leaves "應" at 0.526.)
                    let shareGive = quarterEach > em / 4 ? 0.54 : cellWindows ? 0.52 : autoGive   // (lab `asp`: five spaces' 3.4 shares as 0.54 of each, 標楷體's digits at 3.0 taking "保" 3.40 over in a cell, Word for Windows; zh-147bdae0's cell "…GPU計算資源供各界申" leaves "請" 3.48 over with a word space, which 0.55 took)
                    let spaceTrail = wordSpaces.filter { sp in sp.k < a && (sp.k + 1 ..< a).allSatisfy { isSpace(units[$0]) } }.reduce(0.0) { $0 + $1.w }
                    let spaceEms: Double = gapStretch()
                    let allSpaces: Double = wordSpaces.reduce(0.0) { $0 + $1.w }
                    let weighedSpaces: Double = wordSpaces.filter { spaceWeighs($0.k) }.reduce(0.0) { $0 + $1.w }
                    let giverRoom: Double = givers.reduce(0.0) { $0 + $1.w * spaceGiveShare($1.k) }
                    // (A hung comma or semicolon weighs the automatic spaces double here too, with no mark on
                    // the line: lab `hcg`, "工，" and "工；" 1.7 short and not 2.7, where "工並" takes 3.7.)
                    let hungComma = hang > 0 && (units[tail] == 0xFF0C || units[tail] == 0x3001 || units[tail] == 0xFF1B)
                    let budgetStretch: Double = spaceEms + autoRoom * (hungComma ? 2.08 : 1) + max(0, weighedSpaces - spaceTrail) * 0.47
                    // (In a cell, Word for Windows, a word space stretches half of itself by this test: lab `cend`
                    // takes "程" 3.01pt over with one automatic space and a word space of 6.0, where whole it
                    // refused from 2.4; zh-147bdae0's "…2 vCPUs）…GPU計算資源供各界申" still leaves "請" 3.83 over,
                    // five automatic spaces and a word space giving.)
                    let oldStretch: Double = spaceEms + autoRoom + allSpaces * (cellWindows ? 0.5 : 1)
                    let oldGive: Double = autoRoom * shareGive + allSpaces / 4
                    let budgetGive: Double = autoRoom * shareGive + giverRoom + tailRoom
                    let sharesStretch: Bool = onCharacterGrid || hangulPiece || (units[a] < 0x2E80 && !circled(units[a])) || (autos.isEmpty && !windowsAfterMarks)
                        || (windowsAfterMarks
                            ? need * budgetStretch <= budgetGive * (width - x + spaceTrail + hair)
                            : need * oldStretch <= oldGive * (width - x + hair))
                    if Self.debugFitLog {
                        let pt = theme.pixelsPerPoint * scale
                        FileHandle.standardError.write(Data("FITS\t\(i)\t\(a)\t\(need / pt)\t\(roomSpaces / pt)\t\(autoRoom / pt)\t\(autos.count)\t\(wordSpaces.count)\t\(wordSpaces.reduce(0.0) { $0 + $1.w } / pt)\t\((width - x) / pt)\t\(halfStretch ? 1 : 0)\t\(sharesStretch ? 1 : 0)\t\(spaceEms / pt)\t\(inCell ? 1 : 0)\t\(windowsAfterMarks ? 1 : 0)\t\(quarterEach / pt)\t\(lineFrom)\t\(piece.b)\t\(budgetGive / pt)\t\(budgetStretch / pt)\t\(spaceTrail / pt)\t\(String(String.UnicodeScalarView(units[a ..< min(a + 7, units.count)].compactMap { Unicode.Scalar(UInt32($0)) })))\n".utf8))
                    }
                    // (A cell's final Hangul word with its stop, Word for Windows, mode 15, Gulim 12, justified (lab ko-stop3): the line gives a quarter of Gulim's 4.0 pt space (em/12), however many spaces it has; flip need 0.92 pass, 1.02 refuse; 6d273a8f.)
                    let koCellFinal = RichTextTheme.wordWindowsPages && document.balancesSpaceWidth && inCell && !legacy && p.style.eastAsian["w:wordWrap"] == "0" && units[a] >= 0xAC00 && units[a] <= 0xD7A3 && a + 2 >= units.count
                    if need <= (koCellFinal ? min(roomSpaces, em / 12) : roomSpaces) + hair, halfStretch, sharesStretch {
                        // (Each gives the same share of what it can.)
                        let share = min(1, (need + 0.02) / max(0.001, roomSpaces))
                        if !latinPulled { for space in givers { adjust[space.k, default: 0] -= space.w * (windowsAfterMarks ? 0.25 : spaceGive(space.k)) * share } }
                        let autoShare = (latinPulled ? roomSpaces : roomAutos) / max(0.001, autos.reduce(0.0) { $0 + (gaps[$1] ?? 0) })
                        for k in autos { adjust[k, default: 0] -= (gaps[k] ?? 0) * autoShare * share }
                        for k in tailSqueezers { adjust[k, default: 0] -= em / 64 * share }
                        if after > 0 { adjust[last - 1, default: 0] -= after }
                        if hang > 0 { adjust[tail, default: 0] -= hang }
                        fits = true
                        wordRest = restPieces
                    }
                }
                // (A Thai stretch's closing "?" hangs past the margin, its whole
                // advance: lab `thq` (Windows, zh-6a4fc013's questions, reprinted
                // alone) — "…อย่างไร?" is taken with the "?" 3.85pt past the limit
                // and the rest of it fitting within 0.6-0.8 of the limit, the line
                // not stretched; the p26 question 7.7 over, 3.9 beyond the hang,
                // is left for the next line. Ours measures the Thai a hair wider
                // than Word's face does, so two points are allowed past the hang.)
                if !fits, theme.wordRules, RichTextTheme.thaiBreaksAtSpaces, last > a + 1, units[last - 1] == 0x3F,
                   (a ..< last).contains(where: { (0x0E01 ... 0x0E5B).contains(units[$0]) }) {
                    let over = x + w - width
                    if over - boxes(last - 1, last) <= _px(2) + hair {
                        adjust[last - 1, default: 0] -= over + 0.02
                        fits = true
                    }
                }
                if Self.debugFitLog, overAtStart { FileHandle.standardError.write(Data("FITR\t\(i)\t\(a)\t\(fits ? 1 : 0)\n".utf8)) }
                if fits {
                    // The line is full: whatever comes next starts another.
                    x = width
                    onFirstLine = false
                    marks = []
                    spaces = []
                    wordSpaces = []
                    let endPiece = pieces[min(pieces.count - 1, pieceIndex + wordRest)]
                    if endPiece.hard { x = 0; lineNumber += 1; width = room(lineNumber); opening = true; lineWide = 0; lineFrom = endPiece.b; lineEms = 0; lineOther = false; lineSpaced = false; lineLatin = false; lineLetters = false; lineBlank = false; lineRaised = false; lineTabbed = false }
                    continue
                }
            }
            if !fits {
                // (Where this line ended, and by how much what opens the
                // next was over: see `breaks` below.)
                if last > a, let end = (0 ..< a).last(where: { !isSpace(units[$0]) }) {
                    breaks.append((end, a ..< piece.b, x + w - after - width))
                }
                // (A piece that opens the next line and is wider than it
                // by no more than the automatic space after it gives that
                // up, as one that ends a line does: the engine would set
                // it on this line, over the margin. zh-e329b438's 17.3pt
                // label cells hold "度" a line — 14pt and its 3.5 before
                // "30" — in Word's print; ours set "速度" on one line.)
                if theme.wordRules, last > a, after > 0, w > width, w - after <= width + hair {
                    adjust[last - 1, default: 0] -= min(after, w - width + 0.02)
                }
                // (An Indic word is not parted by the engine unless it is wider than a line: when its first clusters fit and a later one does
                // not, the whole word opens the next line, and its clusters before this one count in that line's width. 9baed400's cell line
                // "…पर्वतीय वनस्पति": the loop ended the line after "व" and left the next 7.2pt short, so the engine could not set what the
                // loop had squeezed to fit.)
                var carry = 0.0, carryFrom = a
                if theme.wordRules, RichTextTheme.wordWindowsPages, !legacy, !piece.hard, a > 0, !isSpace(units[a - 1]), Self._isIndic(UInt32(units[a])),
                   let wordPieces = Optional(indicWordPieces(pieceIndex)), wordPieces.start < pieceIndex {
                    var whole = 0.0
                    for q in wordPieces.start ... wordPieces.end { whole += pieces[q].w }
                    if whole <= room(lineNumber + 1) + _px(0.01) {
                        for q in wordPieces.start ..< pieceIndex { carry += pieces[q].w }
                        carryFrom = pieces[wordPieces.start].a
                    }
                }
                x = carry
                lineNumber += 1; width = room(lineNumber)
                onFirstLine = false
                marks = []
                spaces = []
                wordSpaces = []
                lineWide = 0
                lineFrom = carryFrom
                lineEms = 0
                lineLatin = false
                lineLetters = false
                lineOther = false
                lineBlank = false
                lineSpaced = false
                lineRaised = false
                lineTabbed = false
            }
            // (An opening mark a line starts with keeps its blank half:
            // squeezing it there is what `w:topLinePunct` asks for, and
            // without it a 9pt cell line of "《" and ten ideographs
            // leaves the eleventh, 1.8pt over, for the next line —
            // zh-6d1afa56's tables, mode 14. Lab `ls` (Word for Windows,
            // 宋体 16pt, 2026-10-14): "（" and 25 ideographs 4 or 6pt over
            // break before the last in modes 14 and 15, in the body and
            // a cell, indented or not, as a line with no mark does. With
            // `w:topLinePunct` the first line's is given up before the
            // fit, `_topLineSqueeze`.)
            // (Not one after an ideographic space, which is a character of
            // the line: zh-70094a34's clauses open "\u{3000}\u{3000}（二）…",
            // and Word's print takes "…设施区域范围内，" 21.75pt over with
            // that "（" giving its half, where ours sent "内，" down.)
            let lineOpener = lineWide == 0 && !lineRaised ? (a ..< last).first { units[$0] != 0x20 && units[$0] != 0x09 } : nil
            // (Spaces a line opens with are no characters of it, and
            // those it ends with stretch nothing.)
            // (Not the spaces it opens with: zh-753cd6a8's cell paragraph
            // "  前一年度…排名，第1名…" ends its first line "…第" in Word's
            // print, the "1" 9.1 over left for the next; counted, its two
            // leading spaces let ours take it as a spaced line's word.)
            if (a ..< piece.b).contains(where: { k in
                units[k] == 0x20 && (lineWide > 0 || (a ..< k).contains { !isSpace(units[$0]) })
            }) { lineBlank = true }
            // (What stands before the tab that takes a first line's label
            // to its hanging indent gives nothing to what comes after it:
            // the tab takes the text to the indent however narrow the
            // label is set. zh-499adba6's cell line "（六）<tab>推動…政策，
            // …負擔制" leaves "度，" 7.1pt over for the next line in Word's
            // print, the comma before it giving 6 — the label's "）" had
            // given ours the rest. Not a tab to another stop, which what
            // is before it may move a stop back: zh-6a4fc013's Thai
            // answers "ตอบ :<tab><tab>…" ran a page long on the Mac with
            // their space held, and zh-ab1ea005's contents lines with a
            // right stop's.)
            let lastTab = theme.wordRules ? (a ..< piece.b).last(where: { units[$0] == 0x09 && leftTabs.contains($0) }) : nil
            if lastTab != nil {
                marks = []
                spaces = []
                wordSpaces = []
            }
            for k in a ..< last {
                if isSpace(units[k]) { if lineWide > 0 { lineOther = true } }
                // (A raised number a line opens with — a note's own — is no
                // character of it, and the space after it no word space:
                // zh-344a8d08's footnote "2 「嚴重…規定」之相關規定。" (mode 15)
                // squeezes its "「", "」" and "。" to keep "定。" in Word's
                // print, where a word space would leave the corner brackets
                // nothing to give, lab `sq-sp`; nor is the "「" after it the
                // line's opener, which keeps its blank half.)
                else if theme.wordRules, lineWide == 0, k < runOf.count, p.runs[runOf[k]].style.script == .superscript { lineRaised = true }
                else {
                    // (A run of Latin characters — a number, a word — is
                    // one character of the line, of its run's em: lab
                    // `dg` (Word 16, mode 15, SimSun 16pt, justified), a
                    // line of 15 ideographs, two commas among them, and
                    // "1234", "5678" takes the next ideograph 12.6pt over
                    // and not 12.8, where 23 ideographs take it 11.8 over
                    // and not 12.0. zh-457a8d62's "…之女104年10" takes
                    // "月" 12.86 over in Word's print.)
                    let latin = units[k] < 0x2E80
                    let continues = latin && k > 0 && lineWide > 0 && units[k - 1] < 0x2E80 && !isSpace(units[k - 1])
                    // (On a character grid, of its em as the grid sets
                    // it: zh-457a8d62's grid of 17.0 for 16pt text leaves
                    // "經" 12.44pt over with two marks and 25 characters —
                    // its marks' halves 8.5 each, as set — which the em
                    // alone took.)
                    if !continues { lineWide += 1; lineEms += ems[k] + (k < runOf.count && runsOffGrid[runOf[k]] ? 0 : gridAdd) }
                    if latin { lineLatin = true; if (units[k] | 0x20) >= 0x61 && (units[k] | 0x20) <= 0x7A { lineLetters = true } }
                }
            }
            if last < piece.b, lineWide > 0 { lineSpaced = true }
            if (a ..< piece.b).contains(where: { units[$0] == 0x09 }) { lineTabbed = true }
            pastFrom = (last ..< piece.b).last(where: { units[$0] == 0x09 }).flatMap { runsPast.contains($0) ? (x + w, $0) : nil }
            x += w + piece.trail
            opening = false
            // (Nor, under the balance, spaces with East Asian text on both
            // sides, wherever on the line: lab tbsp (Mac Word, and Word for
            // Windows' print alike) — zh-799c91cd's "…同意由        （公司名稱）
            // 為授權代表，…負責" takes "負責" with every space a whole 6.00 at
            // 12pt and its "（", "）" and "，" giving 4.7; zh-167ee06c's bold
            // cell "民國   年  月   日止" leaves "止" 1.16 over with eight
            // spaces untouched. Ours gave the spaces and kept the marks.)
            // (Word for Mac: Word for Windows' print agrees on zh-799c91cd
            // but takes nothing it would have on zh-505b9619's "…為3日）。"
            // with them gone — Windows mode keeps the old weighing.)
            let flanked = theme.wordRules && !RichTextTheme.wordWindowsPages && document.balancesSpaceWidth && last > a && piece.b < units.count
                && units[last - 1] >= 0x2E80 && units[piece.b] >= 0x2E80
            // (Spaces inside a stretch — a closing mark kept with what its spaces
            // follow — are the line's word spaces too: zh-e0ca7252's "…費用達", nine
            // underlined spaces, "元(上限，…" stretches them 7 to 8 and leaves
            // "能" 7.3pt over rather than squeeze its three marks.)
            let spacesBefore = wordSpaces.count
            if squeezesSpaces, !flanked, RichTextTheme.wordWindowsPages, last > a {
                for k in a ..< last where units[k] == 0x20 && (a ..< k).contains(where: { !isSpace(units[$0]) })
                    && !(((k + 1) ..< units.count).first(where: { units[$0] != 0x20 }).map { units[$0] == 0x09 } ?? false) {
                    wordSpaces.append((k, boxes(k, k + 1)))
                }
            }
            if squeezesSpaces || pageBox, piece.trail > 0, last < piece.b, !flanked {
                // (A space before a tab is held: its box holds the tab's stretch, and the justified line neither stretches nor squeezes it.)
                let trailing = (last ..< piece.b).filter { units[$0] == 0x20 && !(((($0 + 1) ..< piece.b).first(where: { units[$0] != 0x20 })).map { units[$0] == 0x09 } ?? false) }
                for k in trailing { wordSpaces.append((k, piece.trail / Double(max(1, trailing.count)))) }
            }
            // (What a tab follows is set where the tab stop puts it: the spaces before the line's last tab give nothing.)
            if let tab = (a ..< piece.b).last(where: { units[$0] == 0x09 }) { wordSpaces.removeAll { $0.k < tab } }
            if wordSpaces.count != spacesBefore, let lastSpace = wordSpaces.last { spaceBaseX = x - lastSpace.w }
            if topLinePunct, let k = lineOpener, k > (lastTab ?? -1), own.contains(k), Self._openingUnits.contains(units[k]),
               !(onFirstLine && firstGiven) {
                leadOpeners[k] = units.count
                marks.append(k)
            }
            if RichTextTheme.wordWindowsPages, let k = lineOpener, k > (lastTab ?? -1), own.contains(k), Self._closingUnits.contains(units[k]) { closingOpeners.insert(k) }
            marks.append(contentsOf: own.filter { k in
                k > (lastTab ?? -1) && (k != lineOpener || !(Self._openingUnits.contains(units[k]) || (wideQuote(k) && (units[k] == 0x201C || units[k] == 0x2018))))
            })
            spaces.append(contentsOf: ownSpaces.filter { $0 > (lastTab ?? -1) })
            if after > 0 { spaces.append(last - 1) }
            if piece.hard {
                x = 0
                lineNumber += 1; width = room(lineNumber)
                onFirstLine = false
                marks = []
                spaces = []
                wordSpaces = []
                opening = true
                lineWide = 0
                lineFrom = piece.b
                lineEms = 0
                lineLatin = false
                lineLetters = false
                lineOther = false
                lineBlank = false
                lineSpaced = false
                lineRaised = false
                lineTabbed = false
            }
        }
        // What opens a line and gives some of itself there (a mark of
        // it squeezed for the line's sake) must not then fit the line
        // before, which the engine would let it: zh-89385c94's cell line
        // "考，並研提興利防弊" is 0.55 over and its comma gives 0.57, so
        // the engine took "考，" back onto "核清查及追蹤管", where Word
        // ends the line. The line before's last character is widened
        // by the difference and a quarter point (the engine's widths
        // are not the probe's to the hundredth), less than it spared.
        for b in breaks {
            let given = b.opener.reduce(0.0) { $0 - min(0, adjust[$1] ?? 0) }
            if given > b.over - _px(0.25) { adjust[b.end, default: 0] += given - b.over + _px(0.25) }
        }
        // (What a line's opener gives comes off the line's characters
        // alike rather than off the mark: Word takes it from the mark's
        // left, the line starting that much left of the margin, and the
        // engine can set nothing before a line's first character — a
        // space there is given back, and an invisible joiner is folded
        // into the mark, which would then give from its right, over the
        // character after it. Spread, the line holds what Word's does,
        // and justified, it is set as evenly.)
        for (k, end) in leadOpeners {
            guard let given = adjust[k], given < 0 else { continue }
            let alike = (k ..< min(end, units.count)).filter { !isSpace(units[$0]) && units[$0] != 0xFFFC && !(0xDC00 ... 0xDFFF).contains(units[$0]) }
            guard !alike.isEmpty else { continue }
            adjust[k] = nil
            for c in alike { adjust[c, default: 0] += given / Double(alike.count) }
        }
        // (With the tabs' widths, which the paragraph is laid out by.)
        #if os(Linux)
        if Self.debugWidthCheck {
            // (STARLING_FIT_WIDTH_CHECK=1: where the fit loop's measure (the probe's cluster boxes, summed) and the engine's own line
            // (the same text set on one line) part by more than half a point between two spaces: the first such word of the paragraph.)
            let flat = TextPainter(text: span, textAlign: .left, textDirection: .ltr)
            if !inline.isEmpty { flat.setPlaceholderDimensions(inline.map { $0.dimensions }) }
            flat.layout(minWidth: 0, maxWidth: 1_000_000)
            let pt = theme.pixelsPerPoint * scale
            var reported = 0
            var from = 0
            for k in 1 ... units.count where k == units.count || units[k] == 0x20 {
                defer { from = k + 1 }
                guard k > from, reported < 40 else { continue }
                let probed = boxes(from, k)
                // (The word's own width: the caret at its start to the caret at the space after it (or the line's end). Boxes of the word's
                // last character left a trailing comma out and showed it as a 5.4 pt gap.)
                let startX = flat.getOffsetForCaret(TextPosition(offset: map.painter(from)), Rect.zero).dx
                let endX = k >= units.count ? flat.width : flat.getOffsetForCaret(TextPosition(offset: map.painter(k)), Rect.zero).dx
                let hi = endX, lo = startX
                let gap = (probed - abs(hi - lo)) / pt   // (abs: the one-line painter is .ltr, so an RTL word's carets run backwards)
                if abs(gap) > 0.5 {
                    let word = String(String.UnicodeScalarView(units[from ..< k].compactMap { Unicode.Scalar(UInt32($0)) }))
                    fputs("FITW\t\(i)\t\(from)\t\(probed / pt)\t\(abs(hi - lo) / pt)\t\(gap)\t\(word)\n", stderr)
                    reported += 1
                }
            }
            flat.dispose()
        }
        #endif
        guard !adjust.isEmpty else { return [:] }
        for (k, v) in tabs { adjust[k, default: 0] += v }
        return adjust
    }

    /// Word for Windows' counted closing spaces: where a paragraph's
    /// closing spaces open with U underlined ones and P plain ones follow,
    /// the U and the first min(P, U) of the plain. Those count against the
    /// line as far as they reach past half of it: past the margin by more
    /// than half the measure, the word before them goes down; less, they
    /// hang as any closing spaces. Windows' lab t189 (2026-10-25), on
    /// zh-ae2dd08d p68's "開課地點：" and 65 "_" (13pt 標楷體, 6.5 a space,
    /// a 493.25 measure): U26 hangs to P12 and goes down from P13, U20
    /// from P20 (not P16), U13 never through P60, U0 never; with the
    /// measure 421.25 U26 goes down from P8 — half the measure, not a
    /// constant. No underline is drawn under any of them. Word for Mac
    /// hangs them all, and so does Word for Windows after an ideograph.
    static func _underlinedClosingCounted(_ p: RichParagraph) -> Set<Int> {
        let units = Array(p.text.utf16)
        var closing = units.count
        while closing > 0, units[closing - 1] == 0x20 { closing -= 1 }
        // (After a Latin word only, as the lab's underscores: after an
        // ideograph or a full-width mark they hang — zh-621d8756's forms,
        // "参与人：" and its underlined blank, keep their lines in Word's
        // print, where counting them parted "参与" / "人：".)
        guard closing < units.count, closing > 0, units[closing - 1] < 0x2E80 else { return [] }
        var under = [Bool](repeating: false, count: units.count)
        var at = 0
        for run in p.runs {
            if run.style.underline { for k in at ..< min(at + run.length, units.count) { under[k] = true } }
            at += run.length
        }
        var end = closing
        while end < units.count, under[end] { end += 1 }
        let u = end - closing, plain = units.count - end
        guard u > 0, plain > 0 else { return [] }
        return Set(closing ..< end + min(plain, u))
    }

    /// Whether the engine keeps `a` and `b` on one line (a reading of the
    /// Unicode line breaking rules it follows, for the cases Chinese text
    /// meets): nothing parts a mark that may not start a line from what
    /// is before it, or one that may not end a line from what follows; a
    /// quotation mark from either side; the letters and digits of a word.
    static func _glued(_ a: UInt16, _ b: UInt16, strict: Bool = false) -> Bool {
        if _noStart.contains(b) && (b != 0x30FC || strict) || strict && _smallKana.contains(b) || _noEnd.contains(a) || _quotes.contains(a) || _quotes.contains(b) { return true }
        if a == 0xA0 || b == 0xA0 { return true }
        // (Nor after a guillemet that opens, or before one that closes.)
        if a == 0xAB || b == 0xBB { return true }
        // (Greek and Cyrillic words are whole as Latin ones are: each
        // letter of bug65649's Russian was a stretch of its own, so a
        // word over the margin looked like a letter over, and the spaces
        // never gave for it.)
        // (Not "×" and "÷" among them, signs and no letters.)
        func word(_ u: UInt16) -> Bool {
            (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || (u >= 0xC0 && u <= 0x24F && u != 0xD7 && u != 0xF7)
                || (u >= 0x300 && u <= 0x52F) || (u >= 0x1E00 && u <= 0x1FFF)
        }
        func digit(_ u: UInt16) -> Bool { u >= 0x30 && u <= 0x39 }
        if word(a) && word(b) { return true }
        // (A Latin word is whole but after its hyphens: see `joinsLatin`.)
        if a > 0x20, a < 0x7F, b > 0x20, b < 0x7F, a != 0x2D { return true }
        // (A run of hyphens is kept together: dx2 zh 4cac8c37's "大都会----东方" ends its line with all four; ours parted it "--" | "--东方".)
        if a == 0x2D, b == 0x2D { return true }
        // (1.5, 1,000, 10:30, 2024-10, -5)
        if digit(b), a == 0x2E || a == 0x2C || a == 0x3A || a == 0x2D || a == 0x2F { return true }
        return false
    }

    static let _pauseMarks = Set("，。、；：！？".utf16)
    /// The signs a line may end after only where they are set East Asian
    /// (`_breaksBetween`): "×", "°" and the primes.
    static let _eastAsianSigns: Set<UInt16> = [0xD7, 0xB0, 0x2032, 0x2033, 0x2264, 0x2265]
    static func _isLatinWordUnit(_ u: UInt16) -> Bool { (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) }
    /// Small kana: barred from a line start only under strict kinsoku (`w:strictFirstAndLastChars`).
    static let _smallKana = Set("ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶ".utf16)
    /// Whether the document asks for strict kinsoku.
    @inline(never) static func _strictKinsoku(_ document: RichDocument) -> Bool {
        guard let kept = document.keptSettings["w:strictFirstAndLastChars"] else { return false }
        return !kept.containsSubstring("w:val=\"0\"") && !kept.containsSubstring("w:val=\"false\"")
    }
    /// Whether "…" may begin a line: Word's Japanese list of what may not start one omits it (Chinese lists hold it), and
    /// strict kinsoku or a list of the document's own (`w:noLineBreaksBefore`) is not in play.
    static func _ellipsisMayStart(_ document: RichDocument) -> Bool {
        RichTextTheme.wordWindowsPages && document.eastAsiaLanguage?.hasPrefix("ja") == true && !_strictKinsoku(document)
            && document.keptSettings["w:noLineBreaksBefore"] == nil
    }
    static let _noStart = _hangingUnits.subtracting("”’".utf16)
        .union(",.:;!?%)]}-/‰℃°…～·・ー々〃".utf16)
        // (Small kana may open a line: Word's standard Japanese level does not list them, as 20 of 77 ja-JP prints show
        // — efbb06c2 parts "活動しなくな" from "った研一"; only strictFirstAndLastChars adds them.)
        // (And the vertical two-dot leader "︰", Taiwan's colon: no line of Word's prints opens with it,
        // 13 inside lines; zh-e51c31a7's "…以為共同遵守︰" sends "守︰" down where ours opened a line with it.)
        .union("\u{FE30}".utf16)
    static let _noEnd = _openingUnits.union("([{$#￥＄£".utf16)
    static let _quotes = Set("\"'“”‘’".utf16)

    /// The closing brackets alone (the pair table of JIS X 4051 treats 。、 and the like as their own class).
    static let _closingBracketMarks: Set<Character> = ["）", "》", "」", "』", "】", "〕", "〉", "｝", "］"]
    static let _closingBracketUnits = Set(_closingBracketMarks.flatMap { String($0).utf16 })
    static let _closingUnits = Set(_closingMarks.flatMap { String($0).utf16 })
    /// The marks Taiwan's faces set in the middle of their em, with no
    /// blank half to give (`_fitEastAsianLines`).
    static let _centredUnits = Set("，。、；：！？".utf16)
    /// Corner brackets, which give nothing on a line with word spaces
    /// from 2013's layout on (`_fitEastAsianLines`).
    static let _cornerUnits = Set("「」『』".utf16)
    static let _openingUnits = Set(_openingMarks.flatMap { String($0).utf16 })
    /// The marks that may hang past the margin at a line's end.
    // (The primes too, which Word's line rules keep from a line's start:
    // zh-bfe04e2f's "…31°10′48″N/122°10′43.2″" ends its line with the "″"
    // set at the margin, an em of FangSong past it, and "E；" a line down.)
    // (And the small forms of the closing brackets, on the same list:
    // zh-ab1ea005's "…（劳部发﹝1994﹞" ends its line with the "﹞" set at
    // the margin in Word for Windows' print, where ours took "﹝1994﹞"
    // down whole.)
    @inline(never)
    func _afterHyphenPiece(_ units: [UInt16], _ tail: Int) -> Bool {
        var i = tail - 1
        while i >= 0 {
            let u = units[i]
            if u == 0x20 { return false }
            if u == 0x2D { return true }
            i -= 1
        }
        return false
    }
    static let _latinStopUnits: Set<UInt16> = [0x2C, 0x2E, 0x3B, 0x29, 0x7D]

    /// Windows, a stated mode before 2013, plain Latin text (no East Asian layout), outside cells and
    /// boxes, and the paragraph not turned or right to left.
    @inline(never)
    func _latinStopsRule(latinOnly: Bool, _ document: RichDocument, _ p: RichParagraph) -> Bool {
        guard latinOnly, theme.wordRules, RichTextTheme.wordWindowsPages, let mode = document.compatibilityMode, mode < 15,
              p.cell == nil, !p.style.rightToLeft, !document.hangsLatinStops, document.hangsStopsMinorEA, document.eastAsiaLanguage == "zh-CN",
              p.style.alignment != .justify, !p.text.utf16.contains(where: { $0 >= 0x2E80 }) else { return false }
        // (Lab hang2/hang3: with zh-CN + minorEastAsia the stop hangs in paragraphs with <w:br/> too; 7b3ae3a6, which wraps, has no zh language.)
        return true
    }

    static let _hangingUnits = _closingUnits.union("？”’％′″﹚﹜﹞".utf16)

    /// Punctuation whose ink keeps to the left half of its em, and to
    /// the right half: Word takes half an em off the first of two that
    /// stand together — a closing mark before any of either kind, an
    /// opening mark before another opening one (measured from Word 16's
    /// prints; the question mark and the curly quotes take no part).
    /// Symbols an East Asian run draws from the CJK face itself (see
    /// `styled`), and the face: the Mac's PingFang, the engine's own
    /// fallback for CJK text there; nil where no face is known.
    /// The CJK compatibility ideographs Word 16 for Mac sets in Noto
    /// Sans SC where the run's East Asian face lacks them: every one
    /// Noto Sans SC has, the 122 of U+F900-FAFF in its cmap (lab `cj2`
    /// found the 26 the Chinese sample then used; zh-c15af02e's "勵"
    /// U+F97F, not among them, is Noto's in Word's print too, and so is
    /// every other the corpus holds that Noto has, while U+F909, U+F9B2
    /// and U+FA01, which it lacks, are boxes). The others go to Heiti SC.
    static let _notoCompatibility: Set<UInt32> = [
        0xF900, 0xF901, 0xF902, 0xF903, 0xF905, 0xF906, 0xF90B, 0xF90C, 0xF915, 0xF917, 0xF918, 0xF919, 0xF91A,
        0xF921, 0xF92C, 0xF92D, 0xF92F, 0xF931, 0xF932, 0xF933, 0xF934, 0xF935, 0xF937, 0xF938, 0xF939, 0xF93A,
        0xF943, 0xF947, 0xF948, 0xF949, 0xF94A, 0xF94E, 0xF952, 0xF953, 0xF95E, 0xF962, 0xF963, 0xF964, 0xF965,
        0xF966, 0xF967, 0xF96E, 0xF972, 0xF974, 0xF976, 0xF979, 0xF97A, 0xF97B, 0xF97E, 0xF97F, 0xF980, 0xF984,
        0xF985, 0xF98A, 0xF98B, 0xF98C, 0xF98E, 0xF993, 0xF995, 0xF998, 0xF9AE, 0xF9B3, 0xF9B7, 0xF9BB, 0xF9BD,
        0xF9BE, 0xF9C0, 0xF9C5, 0xF9C6, 0xF9D0, 0xF9D8, 0xF9D9, 0xF9DC, 0xF9DD, 0xF9DE, 0xF9DF, 0xF9E0, 0xF9E2,
        0xF9E3, 0xF9E4, 0xF9E7, 0xF9E9, 0xF9F1, 0xF9F4, 0xF9F5, 0xF9FA, 0xF9FD, 0xF9FF, 0xFA02, 0xFA05, 0xFA06,
        0xFA07, 0xFA08, 0xFA0A, 0xFA0C, 0xFA0D, 0xFA0E, 0xFA0F, 0xFA11, 0xFA13, 0xFA14, 0xFA18, 0xFA1F, 0xFA20,
        0xFA21, 0xFA23, 0xFA24, 0xFA27, 0xFA28, 0xFA29, 0xFA2F, 0xFA33, 0xFA34, 0xFA35, 0xFA37, 0xFA38, 0xFA3A,
        0xFA47, 0xFA49, 0xFA4B, 0xFA5D, 0xFA5E,
    ]
    static let _cjkSymbols: Set<Character> = ["\u{2014}", "\u{2015}", "\u{2026}", "\u{2013}", "\u{2500}", "\u{2501}"]
    #if os(macOS)
    static let _cjkSymbolFamily: String? = "PingFang SC"
    #else
    static let _cjkSymbolFamily: String? = nil
    #endif
    /// The platform's CJK face, as the theme's glyph fallback names it:
    /// what an East Asian run's Roman numerals are drawn in (see `styled`).
    #if os(macOS) || os(iOS)
    static let _cjkFaceFamily: String? = "PingFang SC"
    #elseif os(Windows)
    static let _cjkFaceFamily: String? = "Microsoft YaHei"
    #elseif os(Linux)
    static let _cjkFaceFamily: String? = "Noto Sans CJK SC"
    #else
    static let _cjkFaceFamily: String? = nil
    #endif
    static let _closingMarks: Set<Character> = ["，", "。", "、", "；", "：", "！", "）", "》", "」", "』", "】", "〕", "〉", "｝", "］", "．"]
    static let _openingMarks: Set<Character> = ["（", "《", "「", "『", "【", "〔", "〈", "｛", "［"]
    /// A closing curly quote, which the engine keeps with what it closes
    /// (Unicode's quotation class): where the East Asian line rules are
    /// off it may start a line as a closing mark may. Lab `cq` (windows,
    /// zh-1cfb652b's package): its p6, no `w:lang` under
    /// `w:doNotUseEastAsianBreakRules`, ends a line "…四包" and opens the
    /// next "”责任制" in Word's print wherever "包" fits and "”" does not,
    /// with the quote in Times or in 仿宋, hanging allowed or not, in mode
    /// 14 or 15, and so does "’"; ours carried "包”" down. (Not where
    /// `w:kinsoku` 0 is what turns them off in text of an East Asian
    /// language: zh-b00fef0d's "…条抓块统”" ends its line, the quote
    /// squeezed in, in Word's print; let go, ours sent it down.)
    static func _closingQuote(_ ch: Character) -> Bool { ch == "\u{201D}" || ch == "\u{2019}" }
    /// A Latin closing bracket after an East Asian character: where the
    /// East Asian line rules are off it may start a line — zh-51af781b's
    /// "Table Text" style says `w:eastAsia` en-US, and Word's print ends
    /// a cell's line "…得1 分" and opens the next with ")", where ours
    /// squeezed the line's "；" to keep "分)" together.
    /// (And Latin punctuation: zh-7b125a21's "Body Text" turns `w:kinsoku`
    /// off, and Word's print ends a line "…抑制作用" and opens the next
    /// with the Times "," after it; ours kept "用," together, squeezing
    /// the line's "：" and "，", and every page from 90 on ran behind.)
    /// A Latin opening bracket before an East Asian character: where
    /// `w:kinsoku` 0 lets an opening mark end a line, it may too, in Word
    /// for Windows (lab tend was printed there) —
    /// zh-72da925e's "…治理計畫』(" ends p6's first line in Word's print,
    /// "草案)…" opening the next (lab tend, windows-1: the piece is the
    /// "(" alone, 7.98pt), where ours kept "(草" together and squeezed the
    /// line's marks for both.
    /// Line-end openers are allowed by `w:kinsoku` 0 in East Asian text, or by a plain no-compat file whose language is not East Asian.
    @inline(never) static func _plainOrKinsoku(_ plain: Bool, _ kinsokuOff: Bool, _ ea: Bool) -> Bool { (kinsokuOff && ea) || (plain && !ea) }
    /// A plain no-rules file opens a break after an opener only before East Asian text: Word keeps "（rev40）" whole.
    @inline(never) static func _plainOpenerBreak(_ plain: Bool, _ after: Character) -> Bool { !plain || (after.unicodeScalars.first?.value ?? 0) >= 0x2E80 }

    static func _latinOpener(_ ch: Character, _ after: Character) -> Bool {
        RichTextTheme.wordWindowsPages && "([{".contains(ch) && (after.unicodeScalars.first?.value ?? 0) >= 0x2E80
    }

    static func _latinCloser(_ before: Character, _ ch: Character) -> Bool {
        ")]},.;:!?".contains(ch) && (before.unicodeScalars.first?.value ?? 0) >= 0x2E80
    }

    /// Whether `run`'s East Asian line-breaking rules hold: by its own
    /// `w:lang` East Asian language where it states one, else by the
    /// document's (`RichDocument.eastAsianLineRules`).
    /// (Its paragraph style's next, `named`: zh-fec5fa30's body style is
    /// no child of Normal, which says en-US, and takes the defaults'
    /// zh-TW — Word keeps "，" off a line's start there.)
    static func _eastAsianLineRules(_ run: CharStyle, _ document: RichDocument, named: RichNamedStyle? = nil) -> Bool {
        for xml in [run.keptXML, named?.char.keptXML].compactMap({ $0 }) {
            if let r = xml.rangeOfSubstring("w:eastAsia=\"") {
                return ["zh", "ja", "ko"].contains(String(xml[r.upperBound...].prefix(2)).lowercased())
            }
        }
        return document.eastAsianLineRules
    }

    /// Whether "、" may start a line in `run`: Word's no-line-start rule for it holds only at
    /// compatibility 14 or higher AND an East Asian language of zh or ja (the run's own, its
    /// style's, else the defaults'); below that, or with no such tag, it opens a line whenever
    /// the character before it fits (lab cm236, Word prints c12/c14/c15, face and brackets
    /// irrelevant). 2026-11-14, lenovo-2.
    static func _dunhaoMayStart(_ run: CharStyle, _ document: RichDocument, named: RichNamedStyle? = nil) -> Bool {
        guard RichTextTheme.wordWindowsPages else { return false }
        if (document.compatibilityMode ?? 12) < 14 { return true }
        for xml in [run.keptXML, named?.char.keptXML, document.defaultLangXML].compactMap({ $0 }) {
            if let r = xml.rangeOfSubstring("w:eastAsia=\"") {
                return !["zh", "ja"].contains(String(xml[r.upperBound...].prefix(2)).lowercased())
            }
        }
        return true
    }

    /// Whether `run`'s East Asian language is stated as none (`x-none`),
    /// by its own `w:lang`, else its paragraph style's.
    static func _eastAsianLanguageNone(_ run: CharStyle, named: RichNamedStyle? = nil) -> Bool {
        for xml in [run.keptXML, named?.char.keptXML].compactMap({ $0 }) {
            if let r = xml.rangeOfSubstring("w:eastAsia=\"") { return xml[r.upperBound...].hasPrefix("x-none") }
        }
        return false
    }

    static func closesUp(_ a: Character, _ b: Character, centred: Bool = false) -> Bool {
        // (A centred mark — Taiwan's "。" — gives nothing before a closing
        // bracket, which has no blank half on that side either: lab `cu`
        // (Word 16, mode 15, 新細明體 16pt, zh-TW) sets "。」" and "。）" a
        // full em apart, where "：「", "，「", "、「", "）」", "」」" and
        // "」。" close up by half; under zh-CN all of them close up.
        // zh-457a8d62's line opening "產。」" took a character Word wraps.)
        if centred, "，。、；：！？".contains(a), _closingMarks.contains(b) { return false }
        if _closingMarks.contains(a) { return _closingMarks.contains(b) || _openingMarks.contains(b) }
        return _openingMarks.contains(a) && _openingMarks.contains(b)
    }

    /// The offsets at which a Latin word may be parted: inside one too
    /// long for a line of `textWidth` (every character of it but its
    /// first — Word parts those wherever a line ends), and inside every
    /// one where the paragraph says so. A word here is a stretch of
    /// ASCII with no space in it; only one of twenty characters or more
    /// is measured.
    /// Where a word wider than the line itself starts, after other text:
    /// Word takes such a word to a line of its own before it parts it by
    /// characters — bug65649's cell "1 направление" (49pt wide, the word
    /// 55) is "1" / "направлен" / "ие" in Word's print; the engine
    /// parted the word where the line ran out, "1 направле" / "ние", and
    /// the estimate pages after ran a line long. Measured in cells
    /// narrower than 150pt, for words of three letters or more, and in
    /// the body of a document of no East Asian layout for words of
    /// twenty or more: bug65649's "Замечания: " and 142 underscores is
    /// the label alone and two lines of underscores in Word's print,
    /// where ours parted them after the label and the form ran a line
    /// short.
    /// `_wideWordStarts` for a paragraph off any grid, `textWidth` in
    /// pixels — public for the tests, whose process has no ICU to part
    /// lines by.
    public func wideWordStarts(_ p: RichParagraph, _ document: RichDocument, textWidth: Double) -> Set<Int> {
        _wideWordStarts(p, document, textWidth: textWidth, named: _named(p, document), pitch: nil)
    }

    /// Where a Latin word wider than the line may part after a hyphen
    /// before a digit: Word parts it there rather than at the last
    /// character that fits. zh-b3e887f7's 49.4pt time cells hold
    /// "9:00-" / "9:10" in Word's print, where the engine, keeping a
    /// number whole with its sign, parted "9:00-9" / ":10". (A word
    /// that fits keeps its hyphen: zh-64044a1d's "0932-757839", lab
    /// `hy3`.)
    /// Under East Asian layout, where a Latin word that fits the line may
    /// part after a hyphen between a letter or digit and a digit: Word's
    /// prints part "（104-" / "111年）" (zh-b58b4f0c), "106-" / "109 年"
    /// (zh-b2e0f286), "《2018-" / "2020 年" (zh-a917e13c), "電話：02-" /
    /// "87897530" (zh-e0ca7252) — some seventy such lines in the corpus. A
    /// word wider than the line is parted where the line ends instead.
    func _fittingWordHyphens(_ p: RichParagraph, _ document: RichDocument, textWidth: Double,
                                     named: RichNamedStyle?, pitch: Double?) -> Set<Int> {
        // (Not before 2013's layout in a document that compresses
        // punctuation: there Word keeps "电话0571-85455244" (zh-0104b952,
        // mode 14), "（GB12268-2012）" (zh-10eab555), "国贸路811-819号"
        // (zh-15428325) and zh-64044a1d's phone numbers (mode 11) whole,
        // with room for the first part; the prints that part are of
        // mode 15, or of documents that compress nothing.)
        let compresses = document.characterSpacingControl?.hasPrefix("compressPunctuation") ?? false
        guard theme.wordRules, document.usesEastAsianLayout, textWidth > 1, !p.runs.isEmpty, p.text.utf16.contains(0x2D),
              (document.compatibilityMode ?? 12) >= 15 || !compresses else { return [] }
        let units = Array(p.text.utf16)
        func parts(_ u: UInt16) -> Bool { u == 0x20 || u == 0x0A || u == 0x2028 || u >= 0x2E80 }
        var out: Set<Int> = []
        var k = 0
        while k < units.count {
            guard !parts(units[k]) else { k += 1; continue }
            var end = k
            while end < units.count, !parts(units[end]) { end += 1 }
            let cuts = (k + 1 ..< end).filter { o in
                units[o - 1] == 0x2D && units[o] >= 0x30 && units[o] <= 0x39 && o >= 2 && Self._isLatinWordUnit(units[o - 2])
            }
            if !cuts.isEmpty {
                var at = 0
                var run = p.runs[0].style
                for r in p.runs { if k < at + r.length { run = r.style; break }; at += r.length }
                let style = theme.textStyle(for: run, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                let word = String(decoding: units[k ..< end], as: UTF16.self)
                let painter = TextPainter(text: TextSpan(text: word, style: style), textDirection: .ltr)
                painter.layout(minWidth: 0, maxWidth: 1_000_000)
                if painter.width <= textWidth { out.formUnion(cuts) }
                painter.dispose()
            }
            k = end
        }
        return out
    }

    func _wideWordHyphens(_ p: RichParagraph, _ document: RichDocument, textWidth: Double,
                                  named: RichNamedStyle?, pitch: Double?) -> Set<Int> {
        guard theme.wordRules, textWidth > 1, !p.runs.isEmpty, p.text.utf16.contains(0x2D) else { return [] }
        let units = Array(p.text.utf16)
        func parts(_ u: UInt16) -> Bool { u == 0x20 || u == 0x0A || u == 0x2028 || u >= 0x2E80 }
        var out: Set<Int> = []
        var k = 0
        while k < units.count {
            guard !parts(units[k]) else { k += 1; continue }
            var end = k
            while end < units.count, !parts(units[end]) { end += 1 }
            // (Times of day only — "9:00-9:10", a colon in it: zh-64044a1d's
            // phone numbers, "0932-757839" in words wider than their cells,
            // keep their hyphens in Word's print. That is mode 11 and
            // compresses punctuation; from 2013's layout, or where nothing
            // is compressed, any such word parts there, as one that fits
            // does — `_fittingWordHyphens`: zh-e329b438 (mode 15) sets its
            // 14pt score ranges "29-" / "30" in a 38.1pt cell.)
            let modern = (document.compatibilityMode ?? 12) >= 15 || !(document.characterSpacingControl?.hasPrefix("compressPunctuation") ?? false)
            let cuts = !(units[k ..< end].contains(0x3A) || modern && document.usesEastAsianLayout) ? [] : (k + 1 ..< end).filter { o in
                units[o - 1] == 0x2D && units[o] >= 0x30 && units[o] <= 0x39 && o >= 2 && Self._isLatinWordUnit(units[o - 2])
            }
            if !cuts.isEmpty {
                var at = 0
                var run = p.runs[0].style
                for r in p.runs { if k < at + r.length { run = r.style; break }; at += r.length }
                let style = theme.textStyle(for: run, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                let word = String(decoding: units[k ..< end], as: UTF16.self)
                let painter = TextPainter(text: TextSpan(text: word, style: style), textDirection: .ltr)
                painter.layout(minWidth: 0, maxWidth: 1_000_000)
                if painter.width > textWidth { out.formUnion(cuts) }
                painter.dispose()
            }
            k = end
        }
        return out
    }

    /// The Devanagari words (UTF-16 ranges) of a paragraph wider than the column, which Word cuts where each line fills.
    func _wideIndicWords(_ p: RichParagraph, _ document: RichDocument, textWidth: Double,
                         named: RichNamedStyle?, pitch: Double?) -> [Range<Int>] {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, textWidth > 1, !p.runs.isEmpty,
              p.text.unicodeScalars.contains(where: { $0.value >= 0x905 && $0.value <= 0x939 }) else { return [] }
        let units = Array(p.text.utf16)
        func parts(_ u: UInt16) -> Bool { u == 0x09 || u == 0x20 || u == 0x0A || u == 0x2028 || u == 0xA0 }
        var out: [Range<Int>] = []
        var k = 0
        while k < units.count {
            guard !parts(units[k]) else { k += 1; continue }
            var end = k
            while end < units.count, !parts(units[end]) { end += 1 }
            if end - k >= 6, units[k ..< end].contains(where: { $0 >= 0x905 && $0 <= 0x939 }) {
                var at = 0
                var run = p.runs[0].style
                for r in p.runs { if k < at + r.length { run = r.style; break }; at += r.length }
                let style = theme.textStyle(for: run, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                let painter = TextPainter(text: TextSpan(text: String(decoding: units[k ..< end], as: UTF16.self), style: style), textDirection: .ltr)
                painter.layout(minWidth: 0, maxWidth: 1_000_000)
                if painter.width > textWidth { out.append(k ..< end) }
                painter.dispose()
            }
            k = end
        }
        return out
    }

    func _wideWordStarts(_ p: RichParagraph, _ document: RichDocument, textWidth: Double,
                                 named: RichNamedStyle?, pitch: Double?) -> Set<Int> {
        guard theme.wordRules, textWidth > 1, !p.runs.isEmpty else { return [] }
        let narrowCell = p.cell != nil && textWidth < _px(150)
        // (In East Asian text too, and in a cell of any width, for a word
        // of twenty characters or more after an ideograph or a full-width
        // mark: zh-ff93733d's "3. 線上關懷平台：http://df.ffceap.
        // com.tw/taoyuantraining/", in a 210pt cell, has the address on a
        // line of its own in Word's print, parted at the margin — ours
        // parted it after "：", and every page after ran a line early.)
        let units = Array(p.text.utf16)
        var out: Set<Int> = []
        var k = 0
        // A tab separates words too. Including it in the word after a
        // full-width colon inserted a hard break BEFORE the tab; its
        // held space then occupied an extra blank line before the long
        // Thai word (zh-6a4fc013 Q5). Let the tab and the engine's long-word
        // rule place the following word, without stranding the tab.
        // (The Latin ligatures U+FB00-FB06 are Latin letters, not wide
        // ones: lo-d1e88d77's "coosnﬁgoosoossr…", 36 letters with a ﬁ in
        // it, is one word to Word, which sets it on a line of its own.)
        func wide(_ u: UInt16) -> Bool { u >= 0x2E80 && !(0xFB00 ... 0xFB06).contains(u) }
        func parts(_ u: UInt16) -> Bool { u == 0x09 || u == 0x20 || u == 0x0A || u == 0x2028 || wide(u) }
        while k < units.count {
            guard !parts(units[k]) else { k += 1; continue }
            var end = k
            while end < units.count, !parts(units[end]) { end += 1 }
            // (Up to its first hyphen, which a line may end with: Word
            // sets "Блок разветвительно-" / "изолирующий" in that cell.)
            let part = (k + 1 ..< end).first(where: { units[$0] == 0x2D && $0 + 1 < end }).map { $0 + 1 } ?? end
            // (Only after a space: a word that opens the paragraph is on a
            // line of its own already.)
            // (After a space, as before: in a narrow cell, or in a body
            // not set by the East Asian rules — under them Word parts such
            // a word where it stands. After an ideograph or a full-width
            // mark, anywhere.)
            // (… and under East Asian layout after spaces that follow an
            // ideograph: lab `ww` (Word 16, zh-76d361b2's package) sets
            // "测试文字测试文字 " and 80 underscores on two lines, the
            // underscores alone, and "Note: " and the same where it stands.)
            var before = k - 1
            while before > 0, units[before] == 0x20 { before -= 1 }
            let spaceAfterIdeograph = before >= 0 && wide(units[before])
            // (… and in a cell of any width under East Asian layout, after
            // any space: zh-15f60bac's 282pt cell "…研究院(網址: http://www.tri.
            // org.tw/page/consumer.php)及…" ends its line at "(網址: " in Word's
            // print, the address opening the next and parted at its margin.)
            let afterSpace = k > 0 && units[k - 1] == 0x20
                && (narrowCell || p.cell != nil && document.usesEastAsianLayout
                    || p.cell == nil && (!document.usesEastAsianLayout || spaceAfterIdeograph
                        // (Word for Windows takes a word with letters in it to a line of its own there too:
                        // zh-06c46ba9's "…June 26, 2005, from http://www.civicyouth.org/PopUps/…" (mode 14,
                        // 14pt) ends its line at "from " and parts the address at the next margin; ours
                        // parted it after "ht". Lab `ww`'s underscores, Mac, are parted where they stand.)
                        || RichTextTheme.wordWindowsPages && (k ..< part).contains { (0x41 ... 0x5A).contains(units[$0]) || (0x61 ... 0x7A).contains(units[$0]) }))
            let afterIdeograph = k > 0 && wide(units[k - 1])
            if afterSpace || afterIdeograph, part - k >= (narrowCell && afterSpace ? 3 : 20),
               !(k ..< part).contains(where: { wide(units[$0]) }) {
                var at = 0
                var run = p.runs[0].style
                for r in p.runs { if k < at + r.length { run = r.style; break }; at += r.length }
                let style = theme.textStyle(for: run, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                let word = String(decoding: units[k ..< part], as: UTF16.self)
                let painter = TextPainter(text: TextSpan(text: word, style: style), textDirection: .ltr)
                painter.layout(minWidth: 0, maxWidth: 1_000_000)
                // (At the face's own advances where it has them, as `_span`
                // sets the word: zh-de073ee5's ")" and sixty underscores
                // in 標楷體 are 383pt drawn and 505 by the stand-in's
                // glyphs, which took them for wider than the 479pt cell
                // and sent them to a line of their own, "(請列舉" alone
                // above them; Word's print has the one line.)
                var width = painter.width
                if let face = theme.faceResolver?(run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false),
                   let table = face.advanceTable(bold: style.fontWeight == .bold, italic: style.fontStyle == .italic), let px = style.fontSize, px > 0.5 {
                    width = word.reduce(0.0) { sum, ch in
                        guard let u = ch.unicodeScalars.first?.value, ch.unicodeScalars.count == 1, u >= 0x20, u <= 0x7E, Int(u) - 0x20 < table.count
                        else { return sum + _glyphWidth(style, ch) }
                        return sum + table[Int(u) - 0x20] * px / face.sizeScale + (style.letterSpacing ?? 0)
                    }
                }
                // (Thai by the width it is set at, as `_thaiJoins` has it, not
                // letter by letter: each base letter alone is wider than it
                // stands in a word, and zh-6a4fc013's "คำถามที่ 4 ： บทลง…เป็นเท็จ?"
                // (392.7 of a 467.8 column, after an ideograph and a space)
                // was sent to a line of its own, and the lines of every page
                // after it ran one late, p18 on.)
                if RichTextTheme.thaiBreaksAtSpaces, let px = style.fontSize, px > 0.5,
                   word.unicodeScalars.contains(where: { (0x0E01 ... 0x0E5B).contains($0.value) }) {
                    width = word.utf16.reduce(0.0) { sum, u in
                        if (0x0E01 ... 0x0E5B).contains(u) {
                            return sum + ([0x0E31, 0x0E34, 0x0E35, 0x0E36, 0x0E37, 0x0E38, 0x0E39, 0x0E3A, 0x0E47, 0x0E48, 0x0E49, 0x0E4A, 0x0E4B, 0x0E4C, 0x0E4D, 0x0E4E].contains(u) ? 0 : 0.42 * px)
                        }
                        return sum + 0.5 * px
                    }
                }
                // (After a full-width opening bracket the bracket goes with the word: zh-15f60bac's "（https://www.moea.gov.tw/…"
                // opens a line in Word's print, the "（" with it, as an opener may not end a line; ours ended
                // the line before with "（" and parted the address from its first letter.)
                if width > textWidth {
                    out.insert(k > 0 && afterIdeograph && Self._openingUnits.contains(units[k - 1]) ? k - 1 : k)
                }
                painter.dispose()
            }
            // (What follows a hyphen between Latin letters, wider than the
            // line by itself, opens a line of its own and is parted there:
            // lo-d1e88d77's last bullet, "woosroosﬂoosw-" and a run of
            // letters a line and a half long, has the hyphen end the first
            // line in Word's print and the run fill the next; ours, with no
            // opportunity short enough, set the run's start beside the hyphen.
            // The last hyphen only: what lies between two is kept on the line.)
            if RichTextTheme.wordWindowsPages, end - k > 8 {
                // (A hyphen that is not the last counts when what lies up to the next one is wider than the
                // line: dx2 2f415ce7's URL "…/zh-" / "tw/%E9…%99-" / "/%E9…", each piece after a hyphen opening
                // its own line in Word's print and parted there.)
                for o in (k + 2 ..< end) where units[o - 1] == 0x2D && o + 8 < end
                    && (Self._isLatinWordUnit(units[o]) || units[o] == 0x2F || units[o] == 0x25) && Self._isLatinWordUnit(units[o - 2]) && units[o] < 0x80 {
                    let segEnd: Int = (o ..< end).first(where: { units[$0] == 0x2D }).map { $0 + 1 } ?? end
                    if segEnd < end, segEnd - o < 8 { continue }
                    var at = 0
                    var run = p.runs[0].style
                    for r in p.runs { if o < at + r.length { run = r.style; break }; at += r.length }
                    let style = theme.textStyle(for: run, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                    let painter = TextPainter(text: TextSpan(text: String(decoding: units[o ..< segEnd], as: UTF16.self), style: style), textDirection: .ltr)
                    painter.layout(minWidth: 0, maxWidth: 1_000_000)
                    if painter.width > textWidth { out.insert(o) }
                    painter.dispose()
                }
            }
            k = end
        }
        return out
    }

    /// Under `w:wordWrap` off, the one space a paragraph ends in right
    /// after a mark that may hang: it has nowhere to hang where that mark
    /// already does, and goes to a line of its own — zh-c9f4d690's "（五）
    /// 调查新增…报民航行业主管等部门。 " hangs its "。" past the margin in
    /// Word's print and sets the space on the next line, where ours hung
    /// both and every page from p14 ran a line early. Set as a no-break
    /// space (it takes room) with a break before it; nil elsewhere.
    func _closingSpaceHeld(_ p: RichParagraph) -> Int? {
        guard theme.wordRules, p.style.eastAsian["w:wordWrap"] == "0", p.style.alignment != .right, p.style.alignment != .center else { return nil }
        let units = Array(p.text.utf16)
        guard units.count >= 2, units[units.count - 1] == 0x20, units[units.count - 2] != 0x20,
              Self._hangingUnits.contains(units[units.count - 2]) else { return nil }
        return units.count - 1
    }

    func _looseWordOffsets(_ p: RichParagraph, _ document: RichDocument, textWidth: Double,
                                   named: RichNamedStyle?, pitch: Double?) -> Set<Int> {
        guard theme.wordRules else { return [] }
        let units = Array(p.text.utf16)
        var out: Set<Int> = []
        // (A Latin word touching a Japanese character, in a file that names no compatibility mode and no
        // East Asian layout: Word parts it where the line fills, at any letter (lab latbrk, jpn-z21601833-acd729's
        // "ho|wfar" and "Q|CD"); the engine keeps it whole.)
        if RichTextTheme.wordWindowsPages, document.compatibilityMode == nil, document.hangsLatinStops,
           p.style.eastAsian["w:wordWrap"] != "0" {
            func latin(_ u: UInt16) -> Bool { (u | 0x20) >= 0x61 && (u | 0x20) <= 0x7A }
            // (Japanese text only: punctuation, kana, ideographs and full-width forms; not Hangul.)
            func ja(_ u: UInt16) -> Bool { (u >= 0x3000 && u <= 0x9FFF) || (u >= 0xFF00 && u <= 0xFFEF) }
            var k = 0
            while k < units.count {
                guard latin(units[k]) else { k += 1; continue }
                var e = k
                while e < units.count, latin(units[e]) { e += 1 }
                if e - k >= 2, (k > 0 && ja(units[k - 1])) || (e < units.count && ja(units[e])) {
                    for j in k + 1 ..< e { out.insert(j) }
                }
                k = e
            }
        }
        // (An ellipsis "…" may begin a line in Japanese text: Word's Japanese no-start list does not hold it, as the
        // Chinese lists do — xb jpn 1e9281/ec6c96 set a paragraph's last "…" alone on a line of its own when the
        // "使節であった" before it fills the line; the engine, like our `_noStart`, carried "た…" down together.)
        if Self._ellipsisMayStart(document) {
            for k in units.indices.dropFirst() where units[k] == 0x2026 && units[k - 1] != 0x2026 && units[k - 1] != 0x2025 && units[k - 1] > 0x20
                && !Self._openingUnits.contains(units[k - 1]) { out.insert(k) }
        }
        // (`w:wordWrap` off, as many Chinese documents say: every Latin
        // word parts at any character — but not so as to begin a line
        // with what may not begin one, or end it with what may not end.)
        if p.style.eastAsian["w:wordWrap"] == "0" {
            // (What may not begin a line is the document's East Asian
            // language's list: Word's Simplified Chinese one holds "%",
            // "'" and ">", its Traditional one does not — zh-f94d11c5,
            // `zh-TW`, parts "權重為70" from "%。2.活動…" in Word's print,
            // and "權重為30" from "%。"; ours took "0%。" over together.)
            let traditional = Self._traditionalChinese(document)
            // (Korean is not so: kor-z19581051-22de7d, wordWrap off, ko-KR,
            // keeps "(Zero-Gravity" whole in Word's print, parting from
            // the Hangul before it; all 40 of its line ends in Latin text
            // are at spaces. Ours parted "(Zer|o-" and ran a Hangul word short.)
            let korean = document.defaultLangXML?.containsSubstring("w:eastAsia=\"ko") == true
            // (A Hangul syllable and a Latin opening bracket part, though ICU
            // glues "력(": Word sets "무중력" and sends "(Zero-Gravity" down.)
            if korean {
                for k in units.indices.dropFirst() where units[k] == 0x28 && units[k - 1] >= 0xAC00 && units[k - 1] <= 0xD7A3 {
                    // (A bracket that closes before the next space stays with the
                    // word before it: Word sets "에너지(E_{act})" on one line,
                    // the ")" hung, and parts after it. 22de7d.)
                    var j = k + 1
                    while j < units.count, units[j] != 0x20, units[j] != 0x29 { j += 1 }
                    if j < units.count, units[j] == 0x29 { continue }
                    out.insert(k)
                }
                // (And after a hyphen before a letter, as Latin words part: 222f3f's
                // "캐나다-한국-" / "EU)" in Word's print.)
                for k in units.indices.dropFirst() where units[k - 1] == 0x2D && ((units[k] | 0x20) >= 0x61 && (units[k] | 0x20) <= 0x7A) { out.insert(k) }
                // (And between a Hangul syllable and a Roman numeral (U+2160-217F):
                // 30dbe1 wordWrap off, Word parts "…), 제" from "Ⅴ~Ⅵ부(…" mid-word.)
                for k in units.indices.dropFirst() where units[k] >= 0x2160 && units[k] <= 0x217F && units[k - 1] >= 0xAC00 && units[k - 1] <= 0xD7A3 { out.insert(k) }
            }
            for k in units.indices.dropFirst() where !korean && units[k] > 0x20 && units[k] < 0x7F && units[k - 1] > 0x20 && units[k - 1] < 0x7F {
                let mayStart = !Self._noStart.contains(units[k]) || traditional && (units[k] == 0x25 || units[k] == 0x27 || units[k] == 0x3E)
                if mayStart, !Self._noEnd.contains(units[k - 1]) { out.insert(k) }
            }
            // (And the paragraph's closing spaces wrap as characters do,
            // the last on a line hanging past the margin: zh-621d8756's
            // forms end paragraphs in runs of underlined spaces, and in
            // Word's print "陈述申辩人：（…）" and 56 of them is two lines,
            // "答：" and its spaces five, each line of spaces up to the
            // margin and one over. Ours hung them all past the margin on
            // the text's line. A break after each but the last: the
            // engine hangs a space only where the line ends on it.)
            // (Not set right or centred: zh-c5b5087b's and zh-1563bd74's
            // footers, "X…人民政府发布" and five spaces set right under
            // indents wider than the line, keep one line in Word's print,
            // the spaces hanging; wrapped, the footer grew a line and
            // each page's body lost one.)
            var s = units.count
            while s > 0, units[s - 1] == 0x20 { s -= 1 }
            if s == 0, units.count >= 20, p.cell == nil { RuleTrace.hit("wordwrap0-spaces-only-paragraph-wraps") }
            // (A paragraph of spaces alone too, from twenty: zh-621d8756's 102
            // underlined spaces are two lines of 51 in Word's print.)
            if s > 0 || units.count >= 20, units.count - s > 1, p.style.alignment != .right, p.style.alignment != .center {
                for k in s + 1 ..< units.count { out.insert(k) }
            }
            // (And a long run of them with text after it: zh-621d8756's
            // "                                    （本页不够可以续页）", 81
            // underlined spaces and the note, is 51 spaces to the margin and
            // 30 more with the note after them in Word's print, a fresh
            // print of the whole document the same (lab `trail`, windows:
            // the paragraphs carry `w:wordWrap` 0; with it on, spaces hang
            // and never wrap by count). Ours hung all 81 and set the note
            // at the margin of the next line, the page's closing block a
            // line high. From twenty on, so that a few spaces stay as they
            // were.)
            var runStart: Int? = nil
            for k in 0 ... units.count {
                if k < units.count, units[k] == 0x20 {
                    if runStart == nil { runStart = k }
                } else if let from = runStart {
                    if k < units.count, k - from >= 20 {
                        RuleTrace.hit("wordwrap0-long-space-run-before-text")
                        for j in from + 1 ..< k { out.insert(j) }
                    }
                    runStart = nil
                }
            }
            // (One closing space after a mark that may hang parts from it
            // too, and is set as a character — `_closingSpaceHeld`.)
            if let k = _closingSpaceHeld(p) { out.insert(k) }
            return out
        }
        guard textWidth > 1, textWidth < 50_000, units.count >= 20 else { return [] }
        let hyphenated = _autoHyphenPoints(p, document)
        var k = 0
        while k < units.count {
            guard units[k] > 0x20, units[k] < 0x7F else { k += 1; continue }
            var end = k
            while end < units.count, units[end] > 0x20, units[end] < 0x7F { end += 1 }
            if end - k >= 20 {
                var at = 0
                var run = p.runs[0].style
                for r in p.runs { if k < at + r.length { run = r.style; break }; at += r.length }
                let style = theme.textStyle(for: run, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, gridPitch: pitch)
                // (A word with hyphens parts after them first, as Word does:
                // only a piece wider than the line is parted anywhere, where
                // the line ends. LibreOffice's tdf170672 has a 40-letter
                // "(…S-…g)" in a 189pt cell; Word sets "(OOSOOSSOOS-" on a
                // line of its own and the rest under it, and ours cut it
                // after 7 letters on the line before — a line short in
                // the cell, and the rows of 48 pages a line off.)
                var pieces: [Range<Int>] = []
                var from = k
                for o in (k + 1) ..< end where units[o - 1] == 0x2D && units[o] != 0x2D {
                    pieces.append(from ..< o); from = o
                }
                pieces.append(from ..< end)
                for piece in pieces {
                    let word = String(decoding: units[piece], as: UTF16.self)
                    let painter = TextPainter(text: TextSpan(text: word, style: style), textDirection: .ltr)
                    painter.layout(minWidth: 0, maxWidth: 1_000_000)
                    if painter.width > textWidth {
                        if hyphenated.isEmpty || !hyphenated.contains(where: { piece.contains($0) && $0 > piece.lowerBound }) {
                            // (Not right after an opening bracket the word begins with: zh-15f60bac's "（https://www.moea.gov.tw/…"
                            // stands whole on a line of its own in Word's print, the "(" with it; ours left it
                            // at the end of the line before and parted the address from its second character.)
                            for o in (piece.lowerBound + 1) ..< piece.upperBound where !(o == piece.lowerBound + 1 && [0x28, 0x5B, 0x7B].contains(units[piece.lowerBound])) { out.insert(o) }
                        } else {
                            // (Automatic hyphenation on: the line is parted at the LAST hyphenation point that fits
                            // with its hyphen, and only where none does at the character the line ends on — zh-147bdae0's
                            // "(https://www.ndc.gov.tw/Con-" / "tent_List.aspx?n=…" and "…/lflt/in-" / "dex.html)".)
                            func width(_ r: Range<Int>) -> Double {
                                let p = TextPainter(text: TextSpan(text: String(decoding: units[r], as: UTF16.self), style: style), textDirection: .ltr)
                                p.layout(minWidth: 0, maxWidth: 1_000_000)
                                defer { p.dispose() }
                                return p.width
                            }
                            let hyphenWidth = width(0x2D ..< 0x2E)
                            var s = piece.lowerBound
                            while s < piece.upperBound, width(s ..< piece.upperBound) > textWidth {
                                var e = s + 1
                                while e < piece.upperBound, width(s ..< (e + 1)) <= textWidth { e += 1 }
                                if let h = hyphenated.filter({ $0 > s && $0 <= e && width(s ..< $0) + hyphenWidth <= textWidth }).max() {
                                    s = h
                                } else {
                                    out.insert(e); s = e
                                }
                            }
                        }
                    }
                    painter.dispose()
                }
            }
            k = end
        }
        return out
    }

    /// Whether the document's East Asian text is Traditional Chinese,
    /// so that Word's `zh-TW` line-breaking lists hold: by the kept
    /// `w:noLineBreaksBefore`'s language, else the settings' theme
    /// font language, else the defaults' `w:lang`.
    static func _traditionalChinese(_ document: RichDocument) -> Bool {
        func traditional(_ xml: String?) -> Bool? {
            guard let xml, let r = xml.rangeOfSubstring("w:eastAsia=\"") else { return nil }
            let tag = xml[r.upperBound...].prefix { $0 != "\"" }
            return tag == "zh-TW" || tag == "zh-HK" || tag == "zh-MO"
        }
        if let kept = document.keptSettings["w:noLineBreaksBefore"] {
            return kept.containsSubstring("w:lang=\"zh-TW\"") || kept.containsSubstring("w:lang=\"zh-HK\"")
        }
        return traditional(document.themeFontLangXML) ?? traditional(document.defaultLangXML) ?? false
    }

    /// Whether a word joiner goes between `a` and `b`: two characters
    /// of one Latin word (see `_span`) after the first of which the
    /// engine may break — a stroke, a question or exclamation mark, a
    /// bar, a closing bracket.
    /// Whether paragraphs `a` and `b` (in that order) share one border
    /// box: Word's grouping of consecutive paragraphs whose borders and
    /// indents are the same, in the same cell.
    /// A paragraph that is only the break which ends its line, the rest of the same paragraph on
    /// the next page or column: Word shades its line and draws no box round it, and the rest
    /// opens a box of its own (lab bdr2, b2; lo-cbb7657e's boxes).
    func _emptyBreakFragment(_ k: Int, _ document: RichDocument) -> Bool {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, k >= 0, k + 1 < document.paragraphs.count,
              document.paragraphs[k].text.isEmpty, document.paragraphs[k].image == nil,
              document.paragraphs[k].style.borders != nil, document.paragraphs[k].cell == nil else { return false }
        let n = document.paragraphs[k + 1].style
        return n.pageBreakBefore && (n.breakEndsPrevious || n.continuesParagraph)
    }

    func _bordersJoin(_ a: Int, _ b: Int, _ document: RichDocument) -> Bool {
        guard theme.wordRules, a >= 0, b < document.paragraphs.count, a < b else { return false }
        if _emptyBreakFragment(a, document) || _emptyBreakFragment(b, document) { return false }
        let x = document.paragraphs[a], y = document.paragraphs[b]
        guard let bx = x.style.borders, bx == y.style.borders, x.cell == y.cell,
              x.style.indentLeft == y.style.indentLeft, x.style.indentRight == y.style.indentRight else { return false }
        // (Not across a page or column break at the paragraph's start: its box
        // opens again on the new page, with its top line and room — lab pb
        // (Word for Windows) over LibreOffice's tdf153964_firstIndentAfterBreak14,
        // text 4.0pt lower under a border of sz 24 and space 1, 8 under space 8.)
        // (In modes 14 and 15 alike (bdr3) the pieces of a paragraph a break parts, and a
        // paragraph after one that ended in the break, are one box with its
        // top on the first and its bottom on the last: lab bdr2 (Word for
        // Windows), b1/b3/b4, text at the page's top under no top line.)
        // (Not a paragraph that opens with its own break: its box opens on the new page with
        // its top line, whatever stands before it — lo-cbb7657e's "column break2".)
        let oneBox = RichTextTheme.wordWindowsPages && !x.text.isEmpty && (y.style.continuesParagraph || y.style.breakEndsPrevious)
            && (document.compatibilityMode ?? 12) >= 14
        if y.style.pageBreakInline, y.cell == nil, !oneBox { return false }
        // (Nor after a page break that ended the paragraph before: the
        // paragraph after it is first on the new page, its box open there
        // with its top line — lab bdr, C: "afterbreak" at the margin under a
        // 3pt top line; lo-cbb7657e drew none of its boxes' lines.)
        if y.style.pageBreakBefore, !y.style.columnBreak, RichTextTheme.wordWindowsPages, y.cell == nil, !oneBox { return false }
        return true
    }

    /// Word's Korean word, whole between spaces: two Hangul syllables, or a syllable beside an ASCII mark, a quote or
    /// a middle dot or a digit with no space between (dx2 20bb671d's "제1저자" and "10평점" went down whole; 004d7a's "영역(박스)을" went to the next line whole).
    /// Boundaries where `_span` holds a Korean word whole (the zero-width joiner it inserts): the fitter's
    /// pieces must not part there either, or it models breaks the painter never makes.
    @inline(never)
    static func _hangulJoins(_ p: RichParagraph, inserts: [Int], units: [UInt16], wordRules: Bool) -> Set<Int> {
        guard wordRules, RichTextTheme.wordWindowsPages, p.style.eastAsian["w:wordWrap"] != "0" else { return [] }
        var out = Set<Int>()
        let tokens = _koreanTokenJoins(units)
        for o in inserts where o > 0 && o < units.count && (_hangulHeldPair(UInt32(units[o - 1]), UInt32(units[o])) || _fullwidthOperatorHeld(UInt32(units[o - 1]), UInt32(units[o])) || tokens.contains(o)) { out.insert(o) }
        return out
    }

    /// Word keeps a space-free word that holds Hangul whole at the line end, Hanja and marks inside it too
    /// (dx2 b8f72871: '"初聲二字三字合用竝書(초성이자삼자합용병서),' went down whole, where the engine parted it
    /// after 書). The offsets inside such a word that also holds a Hanja, where it must not part.
    @inline(never)
    static func _koreanTokenJoins(_ units: [UInt16]) -> Set<Int> {
        func hangul(_ v: UInt16) -> Bool { v >= 0xAC00 && v <= 0xD7A3 }
        func hanja(_ v: UInt16) -> Bool { (v >= 0x3400 && v <= 0x9FFF) || (v >= 0xF900 && v <= 0xFAFF) }
        func part(_ v: UInt16) -> Bool { hangul(v) || hanja(v) || (v > 0x20 && v < 0x7F) || (v >= 0x2018 && v <= 0x201D) || v == 0xB7 }
        guard units.contains(where: hanja), units.contains(where: hangul) else { return [] }
        var out = Set<Int>()
        var start = 0
        func close(_ end: Int) {
            guard end - start > 1, units[start..<end].contains(where: hangul), units[start..<end].contains(where: hanja) else { return }
            for o in (start + 1)..<end where part(units[o - 1]) && part(units[o]) { out.insert(o) }
        }
        for i in 0..<units.count where units[i] == 0x20 || units[i] == 0x09 || units[i] == 0x0A || units[i] == 0xA0 || units[i] == 0x2028 {
            close(i); start = i + 1
        }
        close(units.count)
        return out
    }

    static func _fullwidthOperatorHeld(_ a: UInt32, _ b: UInt32) -> Bool {
        (a == 0xFF1D || a == 0xFF0B) && (b == 0x28 || (b >= 0x30 && b <= 0x39))
    }

    static func _hangulHeldPair(_ a: UInt32, _ b: UInt32) -> Bool {
        func hangul(_ v: UInt32) -> Bool { v >= 0xAC00 && v <= 0xD7A3 }
        func mark(_ v: UInt32) -> Bool { (v > 0x20 && v < 0x3A) || (v >= 0x3A && v < 0x41) || v == 0x5B || v == 0x5D || v == 0x7B || v == 0x7D || (v >= 0x2018 && v <= 0x201D) || v == 0xB7 }
        return (hangul(a) && (hangul(b) || mark(b))) || (mark(a) && hangul(b))
    }

    public static func joinsLatin(_ a: Character, _ b: Character, eastAsian: Bool = false) -> Bool {
        // (A mathematical letter or digit after it counts as one of the
        // Latin text's own: bug59058's formulas are runs of "𝑏𝑖𝑐𝑖/𝑁𝑖"
        // with no space, which Word carries to the next line whole where
        // the engine parted them after the slash.)
        // (… and so is every pair in such a formula with a mathematical
        // letter or operator in it: the engine also parted "OR𝑖" from
        // "∑𝑘𝑖=1", and Word keeps the space-free formula one word.)
        func mathy(_ c: Character) -> Bool {
            guard let v = c.unicodeScalars.first?.value else { return false }
            // (Not "×" under East Asian layout, where it is a sign Word
            // parts a line after: zh-b56eeded's "…總數)×" ends a line
            // before "100%" in Word's print, and ours carried it down.)
            return (v >= 0x1D400 && v <= 0x1D7FF) || (v >= 0x2200 && v <= 0x22FF) || (v == 0xD7 && !eastAsian)
        }
        func plain(_ c: Character) -> Bool {
            guard let v = c.unicodeScalars.first?.value else { return false }
            return v > 0x20 && v != 0xA0 && (v < 0x2E80 || mathy(c))
        }
        if mathy(a) || mathy(b), plain(a), plain(b) { return true }
        let math = b.unicodeScalars.first.map { $0.value >= 0x1D400 && $0.value <= 0x1D7FF } ?? false
        // (Any letter or digit of an alphabet after the stroke and the
        // rest, not ASCII's alone: bug65649's "ИО102-20/А2М" parts after
        // the hyphen in Word's print and went down whole as "А2М" from
        // "20/" in ours.)
        if let x = a.asciiValue, x == 0x2F || x == 0x3F || x == 0x21 || x == 0x7C || x == 0x29 || x == 0x5D || x == 0x7D,
           !b.isWhitespace, plain(b) {
            return true
        }
        guard let x = a.asciiValue, let y = math ? 0x41 : b.asciiValue, y > 0x20, y < 0x7F else { return false }
        // (And a stop, comma, colon or semicolon before an opening
        // bracket: the engine parts "population." from "(4)Temporality:"
        // — Unicode lets a line break after a stop before a bracket —
        // where Word, which parts Latin text at spaces and after hyphens
        // alone, carries "population.(4)Temporality:" over whole:
        // bug59058's page 29.)
        return (x == 0x2E || x == 0x2C || x == 0x3A || x == 0x3B) && (y == 0x28 || y == 0x5B || y == 0x7B)
    }

    /// Whether a line may break between `a` and `b` for a curly quote's
    /// sake: before an opening one that follows East Asian text or a
    /// closing mark, after a closing one that East Asian text or an
    /// opening mark follows.
    static func _breaksBetween(_ a: Character, _ b: Character, percentStarts: Bool = false, timesEastAsian: Bool = true, shapesPart: Bool = false, latinQuotes: Bool = false) -> Bool {
        func wide(_ c: Character) -> Bool { (c.unicodeScalars.first?.value ?? 0) >= 0x2E80 }
        // (And before a percent sign after a full-width character, where
        // the document's own list of what may not start a line leaves it
        // out (`_percentStarts`): zh-505b9619's lists Taiwan's, and Word's
        // print ends a line "…契約價金總額＿" and starts the next "%(由機關
        // …"; the engine keeps a sign with what it follows.)
        // (And before a full-width one after a digit too: zh-499adba6
        // (zh-TW, no list of its own — Taiwan's, which has neither) ends a
        // line "…總幹事占比為38.54" and starts the next "％，女性理事…".)
        // (And between a geometric symbol set East Asian and the blank
        // fill that follows it: zh-e0ca7252's "止；□" + "_________之日止"
        // keeps its "□" on the line in Word's print, lab sqz8, the
        // underscores starting the next; ours glued them as one word and
        // took the "□" down with them.)
        // (Between the two dashes of a doubled em dash, Word for Windows: jpn-z21601833-acd729's "…自然な顔——だが" ends a line
        // "…顔—" and opens the next "—だが"; the engine keeps the pair together.)
        if shapesPart, a == "\u{2014}", b == "\u{2014}" { return true }
        // (After a minus sign before an ideograph, Word for Windows: jpn-z21601833-c2301a's "…（＋頂点数−−頂点数）" ends a line
        // "…頂点数−−" and opens the next "頂点数）"; the engine reads the minus as a prefix of what follows and carried
        // "−−" down, a line behind.)
        if shapesPart, a == "\u{2212}", let v = b.unicodeScalars.first?.value, v >= 0x3400, v <= 0x9FFF { return true }
        if b == "_", a.unicodeScalars.first.map({ $0.value >= 0x25A0 && $0.value <= 0x25EF }) == true { return true }
        if percentStarts, b == "%", wide(a), !_openingMarks.contains(a) { return true }
        if percentStarts, b == "％", wide(a) && !_openingMarks.contains(a) || a.isASCII && a.isNumber { return true }
        // (And after a plus sign before an ideograph, which the engine
        // keeps with what it prefixes, as a sign with its number:
        // zh-c0ac6f55's "互联网+监管" ends a line "…互联网+" in Word's
        // print, zh-26660336's "…+营业收入…" and zh-41907c96's "互联网+医疗
        // 健康" too; ours took the "+" down and the paragraph ran behind.)
        if a == "+", wide(b), !_closingMarks.contains(b) { return true }
        if b == "\u{201C}" || b == "\u{2018}" {
            // (Not between a closing quote and an opening one that both stand
            // in a Latin face: the pair is one word to Word, and a closing
            // quote may not open a line, so the ideograph before it goes down
            // with it. Lab `cq1` (Word 16, Windows), 04/05/07/08: "暑”“往"
            // with "”“" in Times parts before "暑" at any room, 7.1pt quotes
            // hung or not; in 仿宋 they part between the quotes.)
            if latinQuotes, a == "\u{201D}" || a == "\u{2019}" { return false }
            return wide(a) && !_openingMarks.contains(a) || a == "\u{201D}" || a == "\u{2019}"
        }
        // (And before a hyphen: zh-84702a67's "…系统”-“企业信息备案模块”"
        // parts "”" from "-“" in Word's print, the hyphen opening the
        // line — Word's Simplified Chinese list does not keep a hyphen
        // from a line's start.)
        if a == "\u{201D}" || a == "\u{2019}" {
            return wide(b) && !_closingMarks.contains(b) && !"？！％…".contains(b) || b == "-"
        }
        // (And before a hyphen after an ideograph, which the engine
        // keeps with it: zh-1a3c7aa0's chemical names part "…三甲基" from
        // "-4,6-二氨基…" in Word's print, where ours took "基-4,6-" over
        // whole and left the line a character short.)
        // (And before a slash, which no line-start list holds either:
        // zh-21421b7d's "法人/其他组织", two characters a line in a narrow
        // cell, is "法人", "/其", "他组", "织" in Word's print — the
        // engine kept "人/" together and left "法" alone on the first.)
        // (After a full-width colon too: zh-40fe33a3's cell "…103年：-8.4%"
        // ends a line "…年：" in Word's print and opens the next "-8.4%".)
        if b == "-" || b == "/" {
            // (Not before a slash after a Hangul syllable: kor-z19176375-004d7a's "주변부(대륙붕/연안)성격을"
            // stays whole in Word's print, where ours broke before the "/".)
            if b == "/", let u = a.unicodeScalars.first?.value, u >= 0xAC00 && u <= 0xD7A3 { return false }
            // (And before a slash after a full-width closing bracket, Word for Windows: zh-6e7ff836's
            // cell "…平均值）/ 前3年…" ends a line "…平均值）" and opens the next "/ 前"; see `_span`.)
            return wide(a) && !_openingMarks.contains(a) && (!_closingMarks.contains(a) || b == "-" && a == "："
                || b == "/" && RichTextTheme.wordWindowsPages && "）」』】〉》〕］｝".contains(a))
        }
        // (And between two geometric shapes, which Word parts as it does
        // ideographs: zh-7654804a's "…民間機構○" ends a line in Word's
        // print and "○公司" opens the next; the engine kept "○○" together
        // and the paragraph ran a character behind. From 2013's layout on
        // the Mac: zh-06c46ba9 (mode 14) sends all of "○○○政府" down from
        // "…擬以探討" in Mac Word's print. Word for Windows parts them in
        // every mode: zh-e49d7943 (mode 14) ends a line "…斷裂、○" and opens
        // the next "○至○○段", and zh-06c46ba9's line parts in its print.)
        if shapesPart, let u = a.unicodeScalars.first?.value, let v = b.unicodeScalars.first?.value,
           (0x25A0 ... 0x25FF).contains(u), (0x25A0 ... 0x25FF).contains(v) { return true }
        // (And after one before a Latin word, which the engine keeps with the shape as one word: zh-c9d38b65's
        // "…宁波城市大脑●XX…" ends a line "…城市大脑●" in Word for Windows' print, the shape set an em wide; ours
        // carried "●XX" down and the paragraph ran a character behind.)
        if shapesPart, let u = a.unicodeScalars.first?.value, (0x25A0 ... 0x25FF).contains(u), b.isASCII, b.isLetter || b.isNumber { return true }
        // (And after a multiplication sign, which the engine reads as a
        // letter of the number after it: zh-b56eeded's "…總數)×" ends a
        // line before "100%" in Word's print.)
        // (Only where it is set East Asian — its run hinted so, or its
        // Latin face an East Asian one: zh-8628cfbe's unhinted "用人費用×100%"
        // ends a line "…用人費用" and opens the next "×100%" in Word's
        // print, the sign a letter of the number there.)
        // (A division sign too: zh-5f045fc1's and zh-427cb16c's cells
        // "（被救援民眾滿意度＋一般民眾滿意度）÷2", hinted East Asian, end a
        // line "…）÷" in Word for Windows' print and open the next "2", and
        // zh-b2e0f286's "…之資訊項數÷" the next "8】"; ours carried "÷2" over.)
        if a == "\u{00D7}" || a == "\u{00F7}" { return timesEastAsian && b != " " }
        // (And after "≥" or "≤" set East Asian, the same way: zh-cd8987db's
        // "…每a≥3次。" (hinted, 宋体) ends a line "…每a≥" in Word's print and
        // opens the next "3次。".)
        if a == "\u{2264}" || a == "\u{2265}" { return timesEastAsian && b != " " }
        // (And after a degree sign or a prime, the same way: zh-bfe04e2f's
        // "31°10′48″N/122°10′43.2″E" in FangSong ends one line of Word's
        // print "…43.2″" and starts the next "E；", and another "…31°"
        // before "04′08.9″N…"; the engine keeps the whole as one word.)
        if a == "°" || a == "\u{2032}" || a == "\u{2033}" {
            return timesEastAsian && b != " " && !_closingMarks.contains(b) && !(b.utf16.first.map { _noStart.contains($0) } ?? false)
        }
        // (And after a percent sign before an opening mark a number
        // follows, which Unicode keeps together as one number's sign:
        // zh-20d0e98f's cell ends a line "…）×100%" and opens the next
        // "【107年：", where ours parted "100" from "%【107" and the
        // cell grew a line.)
        if a == "%" || a == "‰" { return _openingMarks.contains(b) }
        return false
    }

    /// Whether the character at `k` is set East Asian as a shared mark is
    /// ("×"): its run hinted so, or its Latin face an East Asian one.
    func _setEastAsian(_ p: RichParagraph, _ document: RichDocument, at k: Int) -> Bool {
        var at = 0
        for run in p.runs {
            if k < at + run.length {
                let named = _named(p, document)
                let hint = run.style.fontHint ?? named?.char.fontHint
                if hint == "eastAsia" { return true }
                let face = theme.faceResolver?(run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false)
                return hint != "default" && (face?.isEastAsian ?? false)
            }
            at += run.length
        }
        return true
    }

    /// Whether "%" may start a line by the document's own list of what may
    /// not (`w:noLineBreaksBefore`), which Word keeps to where it states one,
    /// else by its language's: Taiwan's (and Hong Kong's and Macau's) has
    /// no "%", the mainland's and Japan's have.
    func _percentStarts(_ document: RichDocument) -> Bool {
        guard theme.wordRules else { return false }
        guard let kept = document.keptSettings["w:noLineBreaksBefore"], let r = kept.rangeOfSubstring("w:val=\"") else {
            return document.marksCentred
        }
        let list = kept[r.upperBound...].prefix(while: { $0 != "\"" })
        return !list.containsSubstring("%") && !list.containsSubstring("％")
    }

    /// Whether Word may part a line after a hyphen-minus that opens a
    /// word and a digit follows — a sign, which the engine keeps with its
    /// number: bug59058's p9 table text ends a line " -" and starts the
    /// next "0.01" in Word's print; ours carried "-0.01" down whole.
    /// (After a letter or digit too, outside East Asian layout: `_span`'s
    /// rule from lab `hy3`. `letters` asks for that case as well.)
    static func _breaksAfterHyphen(_ before: Character?, _ a: Character, _ b: Character, letters: Bool = false) -> Bool {
        guard a == "-", b.asciiValue.map({ $0 >= 0x30 && $0 <= 0x39 }) ?? false else { return false }
        if let bb = before, bb.isLetter || bb.isNumber { return letters }
        return before == nil || before == " "
    }

    /// How much of its automatic spaces a compat-14 zh-CN line gives for a line-end comma pair the half-em limit would
    /// carry down (0 when it does not apply): what the pair is over the limit, if the spaces can give that, half each.
    @inline(never)
    static func _digitGapSqueeze(_ document: RichDocument, over: Double, em: Double, marks: Int, gapOf: (Int) -> Double, spaces: [Int], hair: Double) -> Double {
        guard (document.compatibilityMode ?? 12) == 14, document.markSqueezeEm == 0.5, !spaces.isEmpty else { return 0 }
        let limit = em * document.markSqueezeEm * Double(marks + 1) + 0.24
        let need = over - limit
        let room = spaces.reduce(0.0) { $0 + gapOf($1) } / 2
        return need > 0 && need <= room + hair ? need : 0
    }

    /// Whether Word's automatic spacing falls between `a` and `b`: one
    /// an ideograph, kana or hangul, the other a Latin letter (unless
    /// the paragraph turns `w:autoSpaceDE` off) or a digit
    /// (`w:autoSpaceDN`). Punctuation of either script takes none —
    /// and nor does anything in a document not set by the East Asian
    /// rules, which the caller checks.
    static func _autoSpaced(_ a: Character, _ b: Character, _ style: RichParagraphStyle, compat: Int = 12) -> Bool {
        func ideograph(_ c: Character) -> Bool {
            guard let u = c.unicodeScalars.first?.value else { return false }
            switch u {
            // (The katakana middle dot is no ideograph for the automatic space in Word for Windows at compat 15:
            // jpn-z19433747-8787f4's "AI・自動運転・SDV" has no gap beside either dot; compat 14 (930d98) is unmeasured.)
            case 0x30FB: return !(RichTextTheme.wordWindowsPages && compat >= 15)
            case 0x1100 ... 0x11FF, 0x3040 ... 0x30FF, 0x3400 ... 0x9FFF, 0xAC00 ... 0xD7FF, 0xF900 ... 0xFAFF, 0x20000 ... 0x3FFFF: return true
            // (The square units too, in Word for Windows: zh-0060058e's "≤13000㎡，" has its automatic space before
            // the "㎡", and "…三级绿地人" leaves "均" 0.7pt over; without it ours took "均".)
            case 0x3300 ... 0x33FF: return RichTextTheme.wordWindowsPages
            default: return false
            }
        }
        func latin(_ c: Character) -> Bool {
            if c.isASCII { return c.isNumber ? style.eastAsian["w:autoSpaceDN"] != "0" : c.isLetter && style.eastAsian["w:autoSpaceDE"] != "0" }
            guard let u = c.unicodeScalars.first?.value, u < 0x530 else { return false }
            return c.isLetter && style.eastAsian["w:autoSpaceDE"] != "0"
        }
        return (ideograph(a) && latin(b)) || (latin(a) && ideograph(b))
    }

    /// Whether Word sets `ch` in a run's East Asian face: ideographs,
    /// kana, hangul, their punctuation and the full-width forms — and,
    /// in a run hinted East Asian, the quotes, dashes and dots both
    /// scripts claim.
    static func isEastAsian(_ ch: Character, hinted: Bool) -> Bool {
        guard let u = ch.unicodeScalars.first?.value, u >= 0xA0 else { return false }
        switch u {
        case 0x1100 ... 0x11FF, 0x2E80 ... 0x9FFF, 0xA960 ... 0xA97F, 0xAC00 ... 0xD7FF, 0xF900 ... 0xFAFF,
             0xFE30 ... 0xFE6F, 0xFF00 ... 0xFFEF, 0x20000 ... 0x3FFFF:
            return true
        case 0xA1 ... 0x24F, 0x2B0 ... 0x2FF, 0x2010 ... 0x203B, 0x2103, 0x2109, 0x2116, 0x2121, 0x2160 ... 0x217F, 0x2190 ... 0x2199,
             0x2200 ... 0x22FF, 0x2460 ... 0x266F:
            // (The spacing modifier letters too: zh-ab34d9cb's "˙" bullet,
            // U+02D9 hinted East Asian, is 標楷體's full 14pt cell in Word's
            // print.)
            // (Block elements too: zh-340d52e9's "▓", hinted East Asian in
            // a run whose Latin face is 新細明體 and whose East Asian one
            // is Normal's 標楷體, is YaHei Bold in Word's print, its line
            // the taller for it; ours drew it in the Latin face.)
            return hinted
        default:
            return false
        }
    }

    /// True when a step of the squeeze walk measured nothing although it holds
    /// something drawn: the probe could not part its clusters, so the step
    /// takes its width from one unbroken line. (Spaces, controls and the
    /// zero-width joiners draw nothing and may read zero.)
    @inline(never)
    static func _probeCannotMeasure(_ width: Double, _ units: ArraySlice<UInt16>) -> Bool {
        // A step holding a letter of a script whose clusters the probe parts
        // (Indic, Thai, Lao, Tibetan, Myanmar, Khmer) is read whole, even when
        // part of it measured (a Thai word beside Latin sums to a fraction).
        if units.contains(where: { ($0 >= 0x0900 && $0 <= 0x0DFF) || ($0 >= 0x0E00 && $0 <= 0x109F) || ($0 >= 0x1780 && $0 <= 0x17FF) }) { return true }
        return _probeReadsZero(width, units)
    }

    @inline(never)
    static func _probeReadsZero(_ width: Double, _ units: ArraySlice<UInt16>) -> Bool {
        guard width < 0.01 else { return false }
        return units.contains { u in
            u > 0x20 && u != 0xA0 && u != 0x200B && u != 0x200C && u != 0x200D && u != 0x2060 && u != 0xFEFF && !(u >= 0x7F && u <= 0x9F)
        }
    }

}

extension RichLayout {
    /// A text's last word (no space from `a` on) that holds a Hangul syllable.
    @inline(never)
    static func _koreanLastWord(_ units: [UInt16], _ a: Int) -> Bool {
        var hangul = false
        for k in a..<units.count {
            let u = units[k]
            if u == 0x20 || u == 0xA0 || u == 0x3000 { return false }
            if u >= 0xAC00 && u <= 0xD7A3 { hangul = true }
        }
        return hangul
    }

    /// Where Word squeezes the spaces of a left-aligned Latin line: left alignment, below compat 15 (none counts as below), and the
    /// paragraph's text set in a SimSun-class system face (SimSun, NSimSun, FangSong, KaiTi, SimHei). Lab sqz3: SimSun squeezes at
    /// compat 14 with or without useFELayout and with a non-zh eastAsia language; Malgun Gothic does not at 14 or 15 (5 pages
    /// against 4). Keyed on the face, not the language or useFELayout. Centred zh-90e0cea8, Korean ecc32adb and Latin-face
    /// gv-f711169b, fra-g188 stay unsqueezed.
    @inline(never)
    func _leftLatinSqueezeScope(_ document: RichDocument, _ p: RichParagraph) -> Bool {
        guard p.style.alignment == .left, (document.compatibilityMode ?? 11) < 15 else { return false }
        guard let face = p.runs.first?.style.fontFamily ?? _named(p, document)?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily else { return false }
        // (A face property, not a name: Word squeezes where the Latin is fixed at half an em, lab sqz4.)
        return theme.faceResolver?(face, false)?.fixedHalfLatin == true
    }
}
