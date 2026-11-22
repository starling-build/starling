// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "StyledGo": the body of `_spanStyled`

import Flutter
import FlutterSwiftBridge
import Foundation

extension _StyledFrame {
    func go() -> [TextSpan] {
            // (U+FE0F after a text-style emoji draws it in colour, U+FE0E after a colour one as an outline: each such
            // pair is a piece of its own, in its own face.)
            if !ctx.splittingVariation, let pieces = RichLayout._variationPieces(rawText) {
                ctx.splittingVariation = true
                defer { ctx.splittingVariation = false }
                var out: [TextSpan] = []
                var at = base
                for (k, piece) in pieces.enumerated() {
                    let after = k + 1 < pieces.count ? pieces[k + 1].text.first : next
                    let spans = _spanStyled(&ctx, Substring(piece.text), run, at: at, next: after, symbolsShown: symbolsShown)
                    out += piece.kind == 0 ? spans : spans.map {
                        TextSpan(text: $0.text, children: $0.children, style: RichLayout._variationStyle($0.style, kind: piece.kind), recognizer: $0.recognizer, locale: $0.locale)
                    }
                    at += piece.text.utf16.count
                }
                return out
            }
            // (Spaces that lead a run of brackets or marks, in a missing Bengali face (Nikosh, SolaimanLipi) inside a Bengali paragraph, are a piece of their own: Word
            // draws them in Mangal without raising the line, while the bracket after them does; dx2 2263e221's " (" wrapped after its space, 16.4 pt line pitch in Word, 18.4 in ours.)
            if !ctx.splittingSpaces, rawText.count > 1, rawText.first == " ", let cut = rawText.firstIndex(where: { $0 != " " }),
               !rawText[cut...].unicodeScalars.contains(where: { $0.value >= 0x80 || $0.properties.isAlphabetic || $0.properties.numericType != nil }),
               theme.wordRules, RichTextTheme.wordWindowsPages,
               RichLayout._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") != nil,
               p.text.unicodeScalars.contains(where: { $0.properties.isAlphabetic && $0.value >= 0x980 && $0.value <= 0x9FF }) {
                ctx.splittingSpaces = true
                defer { ctx.splittingSpaces = false }
                let n = rawText.distance(from: rawText.startIndex, to: cut)
                RuleTrace.hit("word-spaces-ctx.before-a-bracket-in-a-missing-bengali-face-are-their-own-piece")
                return _spanStyled(&ctx, rawText[rawText.startIndex ..< cut], run, at: base, next: rawText[cut], symbolsShown: symbolsShown)
                    + _spanStyled(&ctx, rawText[cut...], run, at: base + n, next: next, symbolsShown: symbolsShown)
            }
            // (Marks that END a run of Bengali letters, in a face Windows lacks, are a piece of their own: Word draws the colon in Mangal, lifting the line to
            // 1.241 + 0.438 em, as when it is a run of its own; a run that merged with the letters (same flags) took the stand-in's split and stepped 19.3 pt, Word 18.5:
            // dx2 2263e221's "নাম:" and "টিআইএন:".)
            if !ctx.splittingSpaces, rawText.count > 1, theme.wordRules, RichTextTheme.wordWindowsPages,
               let last = rawText.unicodeScalars.last, last.value > 0x20, last.value < 0x7F, !last.properties.isAlphabetic, last.properties.numericType == nil,
               let cut = rawText.lastIndex(where: { !($0.unicodeScalars.first.map { $0.value > 0x20 && $0.value < 0x7F && !$0.properties.isAlphabetic && $0.properties.numericType == nil } ?? false) }),
               rawText.index(after: cut) < rawText.endIndex,
               rawText[...cut].unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF && $0.properties.isAlphabetic }),
               _asciiRunInMissingBengaliFace(run, named, document, rawText[rawText.index(after: cut)...], p.text) {
                ctx.splittingSpaces = true
                ctx.splittingMark = true
                defer { ctx.splittingSpaces = false; ctx.splittingMark = false }
                RuleTrace.hit("word-marks-ending-a-bengali-run-in-a-missing-face-are-their-own-piece")
                let at = rawText.index(after: cut)
                let n = rawText.distance(from: rawText.startIndex, to: at)
                return _spanStyled(&ctx, rawText[rawText.startIndex ..< at], run, at: base, next: rawText[at], symbolsShown: symbolsShown)
                    + _spanStyled(&ctx, rawText[at...], run, at: base + n, next: next, symbolsShown: symbolsShown)
            }
            // (A right-to-left run of figures alone, in a document whose complex-script face is not the Latin one: Word's print draws
            // the digits in the run's Latin face, not the complex-script face the letters take: dx2 79a15231's date cells in
            // Calibri, 5b919053, d5a4662f, f7d88376 and others likewise, where the cs name is a face Windows lacks (B Nazanin) or none; a Hebrew face (font table charset B1) is drawn in Arial, heb xb 95e6b1.)
            hyphenFace = nil
            // (Georgian letters in a run whose face has none: Word's print draws them in Sylfaen, at its 1.317 em line and its widths, where the stand-in
            // drew DejaVu Sans's. dx2 72f67d49, Calibri runs under the theme's Geor = Sylfaen: Word 52 lines at 15.7 pt, ours 55 at 14.5.)
            // (The run's spaces, commas, figures and Latin letters are not Georgian: Word's print draws them in the run's own face, here Arial Bold
            // for an Arial Unicode MS run, a piece each beside the Sylfaen letters: dx2 ka 746c2e0c, words 3.34 pt apart, ours 3.0 at Sylfaen's space.)
            if !ctx.splittingGeorgian, theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, rawText.count > 1 {
                func isKa(_ c: Character) -> Bool { c.unicodeScalars.first.map { $0.value >= 0x10A0 && $0.value <= 0x10FF } ?? false }
                let kaFace = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
                if kaFace != "sylfaen", kaFace != "ghea grapalat", rawText.contains(where: isKa), rawText.contains(where: { !isKa($0) }) {
                    ctx.splittingGeorgian = true
                    defer { ctx.splittingGeorgian = false }
                    RuleTrace.hit("word-georgian-letters-and-their-spaces-are-pieces")
                    var out: [TextSpan] = []
                    var from = rawText.startIndex
                    while from < rawText.endIndex {
                        let ka = isKa(rawText[from])
                        var to = from
                        while to < rawText.endIndex, isKa(rawText[to]) == ka { to = rawText.index(after: to) }
                        let n = rawText.distance(from: rawText.startIndex, to: from)
                        out += _spanStyled(&ctx, rawText[from ..< to], run, at: base + n, next: to < rawText.endIndex ? rawText[to] : next, symbolsShown: symbolsShown)
                        from = to
                    }
                    return out
                }
            }
            if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile {
                var georgian = 0, letters = 0
                for u in rawText.unicodeScalars where u.properties.isAlphabetic { letters += 1; if u.value >= 0x10D0 && u.value <= 0x10FA { georgian += 1 } }
                if georgian > 0, georgian * 2 >= letters {
                    let face = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
                    if face != "sylfaen", face != "ghea grapalat" {
                        RuleTrace.hit("word-georgian-letters-are-sylfaen")
                        run.fontFamily = "Sylfaen"
                        run.hAnsiFontFamily = nil
                    }
                }
            }
            // (ASCII digits inside a right-to-left run of Arabic-script letters, whose complex-script face is a Latin one (Arial, Times New
            // Roman) and whose Latin face is another: Word's print draws the digits in the run's Latin face, the letters in the complex-script
            // one: xb 842f1e's "يونيو 2025" (cs Arial, Calibri digits), 8e6ca0. Each such stretch is a piece of its own, which the rule below
            // for a run of figures alone then sets.)
            if !ctx.splittingDigits, theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, run.rightToLeft, !ctx.splittingVariation,
               rawText.count > 1, rawText.contains(where: { $0.isASCII && $0.isNumber }),
               rawText.unicodeScalars.contains(where: { (0x600...0x6FF).contains($0.value) || (0x750...0x77F).contains($0.value) || (0xFB50...0xFEFF).contains($0.value) }) {
                let csName = (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
                let latinName = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
                if ["arial", "times new roman"].contains(csName), !latinName.isEmpty, latinName != csName,
                   (!(theme.complexFaceKeepsDigits?(latinName) ?? false) || ["calibri", "cambria", "courier new", "cambria math"].contains(latinName)), document.fontCharsets[latinName] != "B2", document.fontCharsets[latinName] != "B1" {
                    var cuts: [Substring.Index] = []
                    var inDigits = false
                    for i in rawText.indices {
                        let d = rawText[i].isASCII && rawText[i].isNumber
                        if d != inDigits { cuts.append(i); inDigits = d }
                    }
                    if !cuts.isEmpty {
                        ctx.splittingDigits = true
                        defer { ctx.splittingDigits = false }
                        RuleTrace.hit("word-ascii-digits-in-an-arabic-rtl-run-take-the-latin-face")
                        var out: [TextSpan] = []
                        var from = rawText.startIndex
                        for c in cuts + [rawText.endIndex] where c > from {
                            let n = rawText.distance(from: rawText.startIndex, to: from)
                            let nextChar: Character? = c < rawText.endIndex ? rawText[c] : next
                            out += _spanStyled(&ctx, rawText[from ..< c], run, at: base + n, next: nextChar, symbolsShown: symbolsShown)
                            from = c
                        }
                        return out
                    }
                }
            }
            // (Word reorders "-", "/" and "%" splits only where the run's complex-script language is not Persian: lab bidi-digits2, with
            // w:lang w:bidi="fa-IR" Word draws 15-13 as written, in any table, face or alignment; without it, 13-15.)
            bidiLanguage = [run.keptXML, named?.char.keptXML].compactMap({ RichLayout._attribute($0, "w:bidi") }).first ?? RichLayout._attribute(document.defaultLangXML, "w:bidi") ?? ""
            wasRightToLeft = run.rightToLeft && !bidiLanguage.hasPrefix("fa")
            if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, run.rightToLeft, !ctx.splittingVariation,
               rawText.contains(where: { $0.isASCII && $0.isNumber }), rawText.allSatisfy({ ($0.isASCII && $0.isNumber) || "/-:.,% ".contains($0) }),
               let latin = run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily, !latin.isEmpty,
               document.fontCharsets[(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()] != "B1",
               !(theme.complexFaceKeepsDigits?(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") ?? false) {
                _ = latin
                run.rightToLeft = false
                // (The hyphen of such a number is drawn in neither the digits' face: lab hyphen-face (Word, 2026-11-14): where the complex-script face is
                // missing from the box it is Arial when the font table has an entry for that face (real or made up) and Cambria when it has none; an
                // installed face (Tahoma) draws it itself. The entry decides, not the name.)
                if rawText.containsSubstring("-") {
                    let csName = (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace()
                    let cs = csName.lowercased()
                    let installed = (theme.complexFaceKeepsDigits?(csName) ?? false) || ["arial", "times new roman", "tahoma", "segoe ui", "microsoft sans serif"].contains(cs)
                    hyphenFace = installed ? csName : (cs.isEmpty || document.fontCharsets[cs] != nil ? "Arial" : "Cambria")
                    RuleTrace.hit("word-rtl-number-hyphen-takes-the-font-table-fallback-face")
                }
            }
            // (A run marked right-to-left in a left-to-right paragraph is an
            // embedding of its own: the one neutral mark that ends its Latin
            // text stands at its start. lo-bbc52bda's "after here:" is
            // ":after here" in Word's print. Moved, not marked: a direction
            // mark would reach the text layer of the PDF.)
            moved = {
                guard theme.wordRules, RichTextTheme.wordWindowsPages, run.rightToLeft, !p.style.rightToLeft,
                      let last = rawText.last, ":;.,!?".contains(last), rawText.count > 2,
                      !rawText.dropLast().contains(where: { ch in ch.unicodeScalars.contains { ArabicForms.isArabic($0.value) || (0x590...0x8FF).contains($0.value) } || ":;.,!?".contains(ch) })
                else { return nil }
                return String(last) + rawText.dropLast()
            }()
            // (A closing run of ideographic spaces Word lets hang is set with no width: _cutTrailingSpaces.)
            // (A line narrower than a glyph, one character wide (a stack): Word sets a character and lets up to five
            // spaces hang after it, and runs of spaces fill lines of six; lab inv28sp sp1-sp3, 26 ideographic spaces
            // take five lines. A space that hangs or is carried on a line is set with no width.)
            stackHung = {
                // compat < 15: in a one-character stack a space takes its own line (lab colindent m14: Word 6 and 11 pages against 5 and 9)
                if theme.wordRules, RichTextTheme.wordWindowsPages, (document.compatibilityMode ?? 12) < 15, textWidth <= 1.01, p.cell == nil,
                   rawText.containsSubstring(" ") {
                    return String(rawText.map { $0 == " " ? "\u{00A0}" : $0 })
                }
            // Word's counts (labs inv28sp, inv28sp2, compat 15): up to 5 spaces hang after a character and runs of spaces fill
            // lines of 6. Prints at 5 pt and 7 pt with different right indents gave the same 5 lines, so the count does not
            // follow the space advance or the line width; it is a fixed rule, not derived from widths.
                guard theme.wordRules, RichTextTheme.wordWindowsPages, (document.compatibilityMode ?? 12) >= 15, textWidth <= 1.01, p.cell == nil,
                      rawText.containsSubstring("\u{3000}") else { return nil }
                let units = Array(p.text.utf16)
                var zero = Set<Int>()
                var k = 0
                while k < units.count {
                    guard units[k] == 0x3000 else { k += 1; continue }
                    var end = k
                    while end < units.count, units[end] == 0x3000 { end += 1 }
                    var at = k
                    if k > 0 { for _ in 0 ..< 5 where at < end { zero.insert(at); at += 1 } }
                    while at < end {
                        let group = min(6, end - at)
                        if group > 1 { for o in (at + 1) ..< (at + group) { zero.insert(o) } }
                        at += group
                    }
                    k = end
                }
                var at = base, out = ""
                for c in rawText { out.append(c == "\u{3000}" && zero.contains(at) ? "\u{200B}" : c); at += c.utf16.count }
                return out
            }()
            hung = {
                guard let idx = index, let cut = _trailCut[idx], base + rawText.utf16.count > cut, rawText.containsSubstring("\u{3000}") else { return nil }
                var at = base, out = ""
                for c in (moved ?? String(rawText)) { out.append(c == "\u{3000}" && at >= cut ? "\u{200B}" : c); at += c.utf16.count }
                return out
            }()
            // (A space right before a danda does not hang in Word: the danda may not start a line, so the space is counted in the fit
            // and the line parts after it; lab dnd2, 33 right indents: "जाएगी " stays on a line only while the word and its space fit, the
            // danda alone below. The engine hangs a trailing space, so it is set as a no-break space with a break after it.)
            spaceBeforeDanda = theme.wordRules && RichTextTheme.wordWindowsPages && rawText.last == " " && (next == "\u{0964}" || next == "\u{0965}")
                && p.text.unicodeScalars.contains(where: { $0.value >= 0x900 && $0.value <= 0x97F })
            text0 = (spaceBeforeDanda ? Substring(String((hung ?? stackHung ?? moved ?? String(rawText)).dropLast()) + "\u{00A0}") : (hung ?? stackHung).map { Substring($0) } ?? moved.map { Substring($0) } ?? rawText)
            // (A space + U+00A0 gap after an Indic letter is not a place to part the line: Word moves the word before it down with
            // the gap and the word after, one unit. Lab nbsp4 (dx2 6dcc4527 p2): "ਵਿਚ" + SP + NBSP + "ਭਾਰਤ" returns to the line only when
            // the edge holds the whole unit (+31 pt), never when just "ਵਿਚ" + SP would fit; NBSP alone parts at +28, SP+NBSP+NBSP at
            // +34, plain spaces never block. The space is set as a no-break space (same width). Cyrillic, Georgian and Armenian gaps
            // (3200cbc7, a6d5c830, c423753e) do part, so only an Indic letter before the gap counts.)
            text = {
                guard theme.wordRules, RichTextTheme.wordWindowsPages, !document.usesEastAsianLayout, text0.containsSubstring(" \u{00A0}") else { return text0 }
                var out = String.UnicodeScalarView()
                var prev: UInt32? = nil
                if base > 0, base - 1 < p.text.utf16.count {
                    prev = p.text.unicodeScalars[p.text.utf16.index(p.text.utf16.startIndex, offsetBy: base - 1)].value
                }
                var changed = false
                let sc = Array(text0.unicodeScalars)
                for (k, u) in sc.enumerated() {
                    if u == " ", k + 1 < sc.count, sc[k + 1].value == 0xA0, let pv = prev, pv >= 0x0900, pv <= 0x0DFF {
                        out.append(Unicode.Scalar(0xA0)!); changed = true
                    } else { out.append(u) }
                    prev = u.value
                }
                if changed { RuleTrace.hit("6dcc4527-indic-space-nbsp-gap-is-one-unit") }
                return changed ? Substring(String(out)) : text0
            }()
            // (A soft hyphen the line ends at is a hyphen to the line breaking
            // too — see `_layoutParagraph`.)
            if let idx = index, let shownSet = _hyphenShown[idx], !shownSet.isEmpty, text.containsSubstring("\u{00AD}") {
                var out = ""
                var at = base
                for ch in text {
                    out.append(ch == "\u{00AD}" && shownSet.contains(at) ? "-" : ch)
                    at += ch.utf16.count
                }
                if out != String(text) { return _spanStyled(&ctx, Substring(out), run, at: base, next: next, symbolsShown: symbolsShown) }
            }
            // (A symbol face's characters drawn as the glyphs they stand
            // for: zh-d0a207ac's Wingdings 2 checkboxes, "£" in the file,
            // drew as "£" in the text's face where Word's print has a box.)
            if !symbolsShown, let glyphs = theme.symbolGlyphs, case let mapped = glyphs(run.fontFamily ?? named?.char.fontFamily, String(text)),
               mapped != String(text), mapped.utf16.count == text.utf16.count {
                return _spanStyled(&ctx, Substring(mapped), run, at: base, next: next, symbolsShown: true)
            }
            latinFace = theme.wordRules || theme.setsFaceAdvances
                ? theme.faceResolver?(run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false) : nil
            // (The face Word sets the Latin characters past ASCII in, where
            // the run names one other than its ASCII face: `w:hAnsi`.)
            highFace = latinFace == nil ? nil : (run.hAnsiFontFamily ?? named?.char.hAnsiFontFamily).flatMap { theme.faceResolver?($0, false) }
            // (Not where the run says `w:hint="default"` over a Latin hAnsi
            // face: its shared marks are that face's then —
            // zh-785e46f8's "产业链“链长" in 仿宋_GB2312 over a Times hAnsi
            // has its "“" in Times in Word's print, 7.1pt, where ours set
            // a full-width one, 16, and the line lost a character.)
            // (zh-7fd860f9's runs say the same hint over a 仿宋_GB2312
            // hAnsi, and their "“" is full-width in Word's print: the
            // hAnsi face decides.)
            hint = run.fontHint ?? named?.char.fontHint
            // (A hint over an East Asian face that is itself a Latin one changes nothing: hin-z21320572's "ç", hinted over
            // Normal's Times New Roman, is drawn in the run's own face in Word's print, its line not the Times line's height.)
            eaFaceIsLatin = theme.wordRules && hint == "eastAsia"
                && (run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily)
                    .flatMap { name in name.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) ? nil
                        : theme.faceResolver?(name, false) }.map { !$0.isEastAsian } == true
            // (A right-to-left run's hinted dash stays its Latin face where the East Asian face is unnamed: heb-z5059159's
            // hinted "–" in Arial in Word's print, where the hint set the left-to-right "·" of fas-z22973278 in MS Mincho.)
            eaNamedNone = run.rightToLeft && theme.wordRules && text.unicodeScalars.allSatisfy({ $0.value == 0x2013 || $0.value == 0x2014 }) && (run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily) == nil
            // (A hint where no East Asian face is named anywhere, over accented Latin letters only: sa2 1f26d09a's "çã"
            // stay the run's own Times in Word's print, its 1.5 lines 20.7 pt, where ours took a fallback face's height, 22.2.)
            eaUnnamedLetters = theme.wordRules && hint == "eastAsia" && !text.isEmpty
                && text.unicodeScalars.contains(where: { $0.value >= 0xC0 && $0.value <= 0x24F })
                && text.unicodeScalars.allSatisfy({ ($0.value >= 0xC0 && $0.value <= 0x24F && $0.value != 0xD7 && $0.value != 0xF7) || $0.value < 0x80 })
                && (run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily) == nil
            hinted = (hint == "eastAsia" && !eaFaceIsLatin && !eaNamedNone && !eaUnnamedLetters) || (latinFace?.isEastAsian ?? false) && (hint != "default" || (highFace?.isEastAsian ?? true))
            // (… but an en dash, unhinted, is its hAnsi face's where that is
            // a Latin one: zh-ea70c30e's "辦公室 – 投訴", `w:ascii` PMingLiU
            // over an inherited Times hAnsi, sets its "–" in Times in Word's
            // print, half an em, where ours drew PMingLiU's at 0.82. Its
            // quotes and other marks stay East Asian: taken as Latin too,
            // eight documents fell.)
            hAnsiFace = highFace ?? (run.fontFamily == nil ? nil
                : (named?.char.hAnsiFontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily).flatMap { theme.faceResolver?($0, false) })
            latinDash = theme.wordRules && (run.fontHint ?? named?.char.fontHint) != "eastAsia" && (latinFace?.isEastAsian ?? false)
                && hAnsiFace.map { !$0.isEastAsian } == true
            // (An em dash, unhinted, is its hAnsi face's where that is an East
            // Asian one over a Latin ascii face: ff493b's "—" in Aptos Bold
            // over a Malgun Gothic hAnsi is Malgun Bold in Word's print, and
            // makes its line 1.73 em tall; ours set it in Aptos.)
            eastDash = theme.wordRules && RichTextTheme.wordWindowsPages && hint == nil
                && (latinFace?.isEastAsian != true || (run.hAnsiFontFamily != nil && run.hAnsiFontFamily != (run.fontFamily ?? named?.char.fontFamily)))
                && (run.hAnsiFontFamily ?? named?.char.hAnsiFontFamily).flatMap { theme.faceResolver?($0, false) }?.isEastAsian == true
            em = (run.fontSize ?? named?.char.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
            // (The run's character scale, Word's `w:w`.)
            wScale = RichTextTheme.wordWidthScale(run.horizontalScale ?? named?.char.horizontalScale ?? 1, wordRules: theme.wordRules,
                eastAsiaFamily: run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily)
            closes = _closesUpMarks(run, named, document)
            // (So may text whose East Asian language has no such rules —
            // its run's own, else the document's: `eastAsianLineRules`.)
            lineRulesOff = kinsokuOff || (theme.wordRules && !RichLayout._eastAsianLineRules(run, document, named: named))
            // A stretch is of one script, and — where the Latin face
            // stands in at a scale for each kind of character — of one
            // kind: -1 East Asian, else the kind (0 where there is one
            // scale for all).
            classed = latinFace?.classScales != nil
            // (A right-to-left run whose Latin face is Arial Narrow: its spaces, digits and marks are the Arabic text's, in Arial, not at the
            // narrow face's widths: the Urdu forms 8963bef7, f98daa05 and 0de57755.)
            narrowLatinInRTL = theme.wordRules && run.rightToLeft && (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily)?.trimmingWhitespace().lowercased() == "arial narrow"
            styles = [:]
            // (The grid's addition to each character, unless the run opts
            // out — or its paragraph: zh-268f8d15's footer, "- 1 -" in a
            // text box whose style sets `w:snapToGrid` 0, is Times's own
            // widths in Word's print on a grid of -0.28 an em; ours set it
            // 1.3pt a character closer, and the box, sized so, lost its
            // closing dash.)
            // (A run off it by its style's characters is off it too, where
            // the run says nothing: zh-c25d08c5's Normal sets the characters'
            // `w:snapToGrid` 0 on a grid of -0.25pt, and Word's print has
            // its 16pt ideographs 16 apart; ours set them 15.75 and took a
            // character more a line.)
            ownGridSay = run.keptXML?.containsSubstring("<w:snapToGrid") ?? false
            runOffGrid = ownGridSay ? (run.keptXML?.containsSubstring("<w:snapToGrid w:val=\"0\"") ?? false)
                : theme.wordRules && (named?.char.keptXML?.containsSubstring("<w:snapToGrid w:val=\"0\"") ?? false)
            // (Latin text too, in a paragraph that takes itself off the
            // grid — not one its style takes off, as zh-268f8d15's footer's
            // and zh-3c055c9b's styles do: zh-c2f6d17a's paragraphs set
            // `w:snapToGrid` 0 on a grid of -0.207pt, and Word's print has
            // their Times digits 7.9 apart, half the grid's addition off
            // 8.0, as on it — ours set them 8.0, and a line of "120" and
            // "48" left a character Word takes.)
            // (On a snapToChars grid the cell is whole: an ideograph takes it, not its own size plus the addition; Latin text keeps its own width.)
            cellFix = _gridCellBase(index, document).map { $0 - em / (theme.pixelsPerPoint * scale) } ?? 0
            grid = theme.wordRules && !runOffGrid && (p.style.eastAsian["w:snapToGrid"] != "0" || p.style.ownGridOff)
                ? _grid(index, document).chars : nil
            // (On a snapToChars grid Latin glyphs keep their plain widths, and a stretch of them stands a whole number of cells: lab gr16a,
            // Word for Windows, "the survey of the coast was" 118.9 pt plain stands 11.0 cells of 11.08, "lighthouse" 47.0 stands 5.)
            latinCell = theme.wordRules && grid != nil ? _gridCellBase(index, document).map { $0 * theme.pixelsPerPoint * scale } : nil
            latinGrid = latinCell != nil ? 0 : grid
            // (Ideographs keep the grid's addition in a paragraph off the
            // grid — not in a run off it, which zh-457a8d62's "(附件一，1頁)"
            // runs are, set at their face's widths in Word's print. Lab
            // `sp`, Word for Windows, zh-3c055c9b's package: its "表標題"
            // text, `w:snapToGrid` 0, at 12pt on a grid of +1pt is set 13
            // apart spaced 0, 12 spaced -0.5 (its style's, counted twice),
            // 10.6 spaced -1.2 — in the body and in a text box alike, and
            // on a grid of -0.5pt 11.5. Ours left the grid out, and the
            // style's spacing then set its 47.8pt header cell "支出傳票"
            // where Word's print has "支出傳". Latin text keeps off it, as
            // zh-268f8d15's footer above.)
            ideographGrid = (grid ?? (theme.wordRules && !runOffGrid ? _grid(index, document).chars : nil)).map { $0 + cellFix }
            // (Where single and double byte widths are balanced, a
            // full-width character takes the run's spacing twice: 16pt
            // text spaced -0.3 is set 15.4 apart.)
            spacing = (run.letterSpacing ?? (theme.wordRules ? named?.char.letterSpacing ?? _normalChar(document)?.letterSpacing : nil) ?? 0)
                * theme.pixelsPerPoint * scale
            doubles = theme.wordRules && document.balancesSpaceWidth && spacing != 0
            // A character an embedded subset lacks (`RichResolvedFace.covers`)
            // is set in the face the name has unembedded, Word's fallback,
            // its line that face's height (kind -3).
            subsetFace = theme.wordRules
                ? theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                      ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true) : nil
            uncovered = subsetFace.flatMap { face in face.uncoveredFamily.flatMap { alt in face.covers.map { (alt, $0) } } }
            // (Where Word takes them from several faces, each its own kind,
            // -10 down: `RichResolvedFace.uncoveredChain`.)
            chain = uncovered != nil ? subsetFace?.uncoveredChain : nil
            chainAt = nil
            cambriaWidth = 0.0
            // (Whether the run's shapes are its Latin face's — no East
            // Asian hint, a Latin face that is not an East Asian one.)
            latinShapes = theme.wordRules && run.fontHint != "eastAsia"
                && theme.faceResolver?(run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false)?.isEastAsian != true
            // (Word's "fit text", `w:fitText`: the runs of one id are spaced
            // to be val/20 pt wide together. Word for Windows, zh-c2c92639's
            // "本标准主要审查人员：" with fitText 2210: the nine ideographs
            // 11.12pt apart, the colon at its own advance, and the next text
            // 110.5pt from the start; the run's own spacing and the grid's
            // addition are gone. Spaced to it here, through the style, so the
            // line fitter sees what is drawn.)
            // (A cell's `w:tcFitText`, Word for Windows, dx2 28dd0ac0 and lab
            // tcfit1: a cell's line wider than the cell is kept on one line and
            // spaced so it ends at the cell's edge (27.72 for 28.2 at 24pt in a
            // 13684-twip cell); a line that fits is left as it is, not stretched.)
            tcFit = theme.wordRules && RichTextTheme.wordWindowsPages && textWidth > 1
                && RichLayout._tcFitParagraph(p, index, document)
            fitGroup = theme.wordRules && RichTextTheme.wordWindowsPages
                ? (RichLayout._fitText(run.keptXML) ?? (tcFit ? (textWidth / (theme.pixelsPerPoint * scale), "tc") : nil)) : nil
            fitPitch = nil
            fitBusy = false
            plainPiece = false
            latinNoScale = false
            // (A run names its Latin face itself, or takes one from its styles that is a Windows Latin face: xd 77d6ca49's ", AIESC" in
            // Calibri (Normal style), 12.0 in Word, 12.48 with the Indic scale.)
            latinFaceNamed = {
                if run.fontFamily != nil { return true }
                guard theme.wordRules, RichTextTheme.wordWindowsPages else { return false }
                // (Devanagari and Gurmukhi paragraphs only: dx2 d611e23b, Telugu with Arial from Normal, draws its Latin at the Indic scale in Word; Gurmukhi: dx2 6af76fa9, Arial from the table style, "(ATAR)" is Arial's own width.)
                guard p.text.unicodeScalars.contains(where: { ($0.value >= 0x905 && $0.value <= 0x939) || ($0.value >= 0xA05 && $0.value <= 0xA39) }) else { return false }
                let f = (named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
                return !f.isEmpty && !f.hasPrefix("nirmala ui") && WordWindowsFaces.names.contains(f)
            }()
            fitNone = false
            fitLastSingle = false
            fitLastEnd = 0
            // (What the painting below sets a character of a fit-text group wider than the stand-in's glyph, so the group's
            // spread is worked out from the widths Word's faces give: Hangul an em, the full-width symbols an em, and the
            // original face's own advance for the ASCII and the punctuation. dx2/xd 89a3482a's 12 pt w:w 87 group is 372 pt
            // and Word's step is 10.44 a letter, spread 0; measuring the stand-in's 9.6 gave 0.7 and the line wrapped.)
            // (Devanagari and Bengali, in Word for Windows: the face Word draws a run in, which sets its line (the joiner below) and its
            // width, as the face's own letters are wider or narrower than the Noto stand-in's — the ratio of the advances in the fonts Word's
            // prints embed, weighted by the letters the pages use: Mangal 1.096, Nirmala UI 1.086 (Bold 1.076, Bengali 1.062), Kokila 0.73.
            // A run mostly of such letters takes it whole. Which face: the complex-script one (Mangal, Kokila), but Kalpurush, which Windows
            // lacks, Word draws in Nirmala UI (ben-z17281487). hin-z18479909's Kokila runs print in Nirmala UI too, where mar-z19707447's and
            // hin-z20740649's, the same markup, print in Kokila: not explained (a print machine without Kokila regular?), the majority taken.)
            // (Kokila as the run's Latin face too: only then are its Latin, digits and space, and its line, Kokila's; with another Latin face
            // (cbb7ae39: Times New Roman beside a Kokila complex face) the Latin keeps that face.)
            kokilaLatin = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "kokila"
            // (The same face seen from a run of Latin: dots, digits, or spaces alone on a line, lab siyam2; spaces after Bengali on its line add nothing.)
            malgunLatin = theme.wordRules && RichTextTheme.wordWindowsPages && document.readFromFile
                && _malgunAlternate(run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily, document)
            // (Arial Unicode MS with the Japanese charset in the font table, no Indic letter in the paragraph: Word prints the Latin text in Yu Gothic, a 1.67 em
            // line; dx2 3922c734, a Danish form, lines 16.7 pt apart at 10 pt against ours 13.4.)
            aumsLatin = theme.wordRules && RichTextTheme.wordWindowsPages && document.readFromFile && document.fontCharsets["arial unicode ms"] == "80"
                && (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms"
                && !p.text.unicodeScalars.contains(where: { RichLayout._isIndic($0.value) || RichLayout._tamil.contains($0.value) || $0.value >= 0x2E80 })
                && !(run.keptXML.map { $0.containsSubstring("<w:cs/>") || $0.containsSubstring("<w:cs ") } ?? false)
            // (Arial Unicode MS in an Indic paragraph, a run with no w:cs: its Latin, digits and marks take the ascii slot, which Word lacks and draws
            // in Yu Gothic, whose line every such run sets whatever it holds; lab aumsy2 (2026-11-09): at 9 pt the steps are 12.8 into and 14.2 out of
            // a Nirmala line, for GST, commas, brackets, dots, digits, "**", regular and bold. fb94294e.)
            // (A Hangul-named face Word's box lacks: its Latin letters, digits and spaces are Yu Gothic's, so they take Yu Gothic's advances; 22de7d.)
            yuOfMissingHangul = aumsLatin || (theme.wordRules && RichTextTheme.wordWindowsPages && _yuLatinOfMissingHangulFace(run, named, document)
                && !document.hasIndicText)
            aumsYuInIndic = theme.wordRules && RichTextTheme.wordWindowsPages && document.readFromFile && document.fontCharsets["arial unicode ms"] == "80"
                && (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms"
                && !(run.keptXML?.containsSubstring("<w:cs/>") ?? false) && !(run.keptXML?.containsSubstring("<w:cs ") ?? false)
                && p.text.unicodeScalars.contains(where: { $0.value >= 0x900 && $0.value < 0xB00 })
            aumsSpaces = theme.wordRules && RichTextTheme.wordWindowsPages && document.readFromFile
                && (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms"
                && p.text.unicodeScalars.contains(where: { $0.value >= 0x900 && $0.value < 0xB00 })
            mangalLatinSpace = theme.wordRules && RichTextTheme.wordWindowsPages && document.readFromFile
                && (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "mangal"
                && p.text.unicodeScalars.contains(where: { ($0.value >= 0x905 && $0.value <= 0x939) || ($0.value >= 0xA05 && $0.value <= 0xA39) })
            utsaahLatin = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "utsaah"
            namedFace = text.unicodeScalars.contains(where: { $0.properties.isAlphabetic && RichLayout._isIndic($0.value) }) ? nil : _namedMetricFace(run, named, document, text)
            // (Kalimati is a face Windows lacks, drawn in Mangal: a space-only paragraph whose MARK is a complex-script one (`w:cs`) takes Mangal's line,
            // as the stand-in cannot; dx2 9baed400's cell paragraph, 31.3 pt in Word's print where ours stood 25.8. A mark with no `w:cs` keeps the
            // Calibri line however the run is flagged: 72d5ef87's two space-only paragraphs, 56.7 pt.)
            namedKalimati = false
            if namedFace == "mangal", !p.text.isEmpty, p.text.unicodeScalars.allSatisfy({ $0.value == 0x20 || $0.value == 0x09 || $0.value == 0x2E || ($0.value >= 0x30 && $0.value <= 0x39) }),
               let kept = p.style.mark?.keptXML, kept.containsSubstring("<w:cs/>") || kept.containsSubstring("<w:cs ") {
                let csK: String = run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? ""
                let asciiK: String = run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? ""
                let csFlagK: Bool = run.keptXML.map { $0.containsSubstring("<w:cs/>") || $0.containsSubstring("<w:cs ") } ?? false
                namedKalimati = (csFlagK ? csK : asciiK).trimmingWhitespace().lowercased() == "kalimati"
            }
            indic = {
                guard theme.wordRules, RichTextTheme.wordWindowsPages else { return nil }
                var count: [Character: Int] = [:], letters = 0
                for u in text.unicodeScalars where u.properties.isAlphabetic {
                    letters += 1
                    let v = u.value
                    if (0x0900 ... 0x097F).contains(v) { count["D", default: 0] += 1 } else if (0x0980 ... 0x09FF).contains(v) { count["B", default: 0] += 1 }
                    else if (0x0A00 ... 0x0A7F).contains(v) { count["P", default: 0] += 1 } else if (0x0A80 ... 0x0AFF).contains(v) { count["G", default: 0] += 1 }
                    else if (0x0C00 ... 0x0C7F).contains(v) { count["T", default: 0] += 1 }
                }
                guard let top = count.max(by: { $0.value < $1.value }) else {
                    // (Thai letters in a run with no w:cs: Word's print draws them in Leelawadee UI, not the run's complex face, and sets the line at its
                    // 1.36 em (16.3 pt at 12 pt). Width: the median of Word's glyph advances over ours is 0.93. Real prints: dx2 fac01c51, aa59e402, 9f1bd17e.)
                    // (Lao letters: Word's print of dx2 30f73046 draws them in Leelawadee UI even in runs with w:cs whose face (Saysettha OT) is missing on Windows;
                    // dx2 1f270ff6 (Phetsarath OT, DokChampa) is drawn in DokChampa, so that face is left out.)
                    let laoFace = (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
                    if text.unicodeScalars.contains(where: { $0.value >= 0x0E81 && $0.value <= 0x0EDF }), laoFace != "phetsarath ot", laoFace != "dokchampa" {
                        RuleTrace.hit("word-lao-letters-are-leelawadee-ui")
                        return ("leelawadee ui", 1)
                    }
                    // (Not where the run's own font is Tahoma, which has Thai: xb 5dc87fc7's print draws a no-w:cs Thai run set in Tahoma in Tahoma, a 14.5 pt line at 12 pt.)
                    let thaiOwnFace = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "tahoma"
                    if !thaiOwnFace, text.unicodeScalars.contains(where: { $0.value >= 0x0E01 && $0.value <= 0x0E5B }),
                       !(run.keptXML.map { $0.containsSubstring("<w:cs/>") || $0.containsSubstring("<w:cs ") } ?? false) {
                        RuleTrace.hit("word-thai-without-cs-is-leelawadee-ui")
                        return ("leelawadee ui", 1)
                    }
                    // (Thaana letters, in any run: Faruma and the rest are missing on Windows and Word draws them in MV Boli, whose line is 1.611 em; dx2 3a5235d0.)
                    if text.unicodeScalars.contains(where: { $0.value >= 0x0780 && $0.value <= 0x07BF }) {
                        RuleTrace.hit("word-thaana-letters-are-an-mv-boli-line")
                        return ("mv boli", 1)
                    }
                    // (A run whose complex-script face carries the font table's Thaana mark and is missing on Windows: Word sets the run whole in MV Boli, its digits, spaces and punctuation too, so a digit-only cell is a 1.611 em line; dx2 e3906782.)
                    if !text.isEmpty, !document.thaanaFaces.isEmpty,
                       document.thaanaFaces.contains((run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased())
                        || (!text.unicodeScalars.contains(where: { ($0.value >= 0x41 && $0.value <= 0x5A) || ($0.value >= 0x61 && $0.value <= 0x7A) || $0.value > 0x7F && !($0.value >= 0x0600 && $0.value <= 0x06FF) && $0.value != 0x2019 })
                            && document.thaanaFaces.contains((run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased())) {
                        RuleTrace.hit("word-thaana-face-run-is-an-mv-boli-line")
                        return ("mv boli", 1)
                    }
                    // (Myanmar letters, in any run: Word draws them in Myanmar Text (Zawgyi-One and the rest are missing on Windows) and sets the line at its 1.861 em.)
                    if text.unicodeScalars.contains(where: { $0.value >= 0x1000 && $0.value <= 0x109F }) {
                        RuleTrace.hit("word-myanmar-letters-are-a-myanmar-text-line")
                        return ("myanmar text", 1)
                    }
                    // (Sinhala letters, in any run: Word draws them in Nirmala UI, whose line is 1.079 + 0.251 em; dx2 827a8947.)
                    if text.unicodeScalars.contains(where: { $0.value >= 0xD80 && $0.value <= 0xDFF }) {
                        RuleTrace.hit("word-sinhala-letters-are-a-nirmala-ui-line")
                        return ("nirmala ui", 1)
                    }
                    // (A paragraph of a Tamil-language document with no Tamil letter, its run a complex-script one (w:cs) whose face is Arial Unicode MS
                    // (missing on Windows): Word sets its line as Nirmala UI's, 1.079 + 0.251 em, with no Leelawadee surplus; dx2 a347c3b3's "00 month 20XX"
                    // stands 1.64 pt lower than the Latin stand-in's line and the next line 0.33 further.)
                    if document.defaultLangXML?.containsSubstring("ta-IN") == true,
                       run.keptXML.map({ $0.containsSubstring("<w:cs/>") || $0.containsSubstring("<w:cs ") }) == true,
                       (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms",
                       !p.text.unicodeScalars.contains(where: { RichLayout._tamil.contains($0.value) }) {
                        RuleTrace.hit("word-tamil-doc-latin-cs-run-is-a-nirmala-ui-line")
                        return ("nirmala ui", 1)
                    }
                    // (Tamil: the line of Nirmala UI, 1.079 + 0.251 em, in the prints of tam-* and four of the xd Tamil documents.)
                    // (Width: set per word in flush() from TamilAdvances, a per-codepoint regression fit of Word's word widths
                    // (2864 words, four documents); our PDF embeds no Tamil face, so it cannot be read from glyph hmtx. No scale here.)
                    if text.unicodeScalars.contains(where: { RichLayout._tamil.contains($0.value) }) {
                        // (Vijaya, when the run's complex face is that: Windows has it, and Word draws it as itself; dx2 c30a7a61.)
                        return (_tamilVijaya(run.complexFontFamily, named, document) ? "vijaya" : "nirmala ui", 1)
                    }
                    // (Malayalam: Word draws it in Nirmala UI, whose line is 1.079 + 0.251 em; dx2 37abe13a's 11 pt body steps 14.64 pt, the stand-in's 12.6.)
                    if text.unicodeScalars.contains(where: { $0.value >= 0xD00 && $0.value <= 0xD7F }) {
                        RuleTrace.hit("word-malayalam-is-a-nirmala-ui-line")
                        return ("nirmala ui", 1)
                    }
                    // (A run with no Indic letter in a Kokila paragraph — dotted leaders, a comma, digits — is Kokila's too, in Word's print: its Latin
                    // face is Kokila as well. Left to the stand-in it set the line by Carlito's split, and stacked with the Kokila runs on the line.)
                    if kokilaLatin,
                       (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "kokila" {
                        return ("kokila", 1)
                    }
                    // (A run with no Indic letter whose ascii and complex faces are both Shonar Bangla, in a Bengali paragraph: Word draws the Latin in Shonar's own
                    // advances too, "[Insert Project Name]" 53.4 pt at 14 pt where the stand-in's Latin gave 74; dx2 3f7da49c.)
                    if (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "shonar bangla",
                       (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "shonar bangla",
                       p.text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF }) {
                        RuleTrace.hit("word-latin-in-a-shonar-bangla-run-is-shonar-bangla")
                        return ("shonar bangla", 1)
                    }
                    // (A run with no Indic letter whose ascii and complex faces are both Vrinda, in a Bengali paragraph, is drawn in Vrinda: its Latin takes
                    // Vrinda's advances and its space is Vrinda's 0.598 em; 06800107's "(NAME OF PLACE)": Word 46.7 pt for "(NAME ", ours 41.8.)
                    if (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "vrinda",
                       (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "vrinda",
                       p.text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF }) {
                        return ("vrinda", 1)
                    }
                    // (A run of only ASCII letters, digits and marks, in a face Windows lacks (SolaimanLipi, Nikosh), inside a Bengali paragraph: Word draws it in Mangal,
                    // at Mangal's advances; xd 73caaeda's "Sterile" 35.5 pt at 12 pt, the comma 3.45, where the stand-in gave 31.1 and 3.0.)
                    if _asciiRunInMissingBengaliFace(run, named, document, text, p.text) {
                        RuleTrace.hit("word-missing-bengali-face-latin-is-mangal-advances")
                        return ("mangal", 1)
                    }
                    // (A Latin-only run whose ascii and complex faces are the SAME face Windows lacks, and which Word draws in Shonar Bangla (the
                    // usb0 rule), in a Bengali paragraph: Word draws the Latin in Shonar Bangla too, at the authored size; lab bnmix2 latK, bfc234.)
                    if let f = _shonarLatinRunFace(run, named, document, p.text) {
                        RuleTrace.hit("word-latin-in-a-missing-bengali-face-run-is-shonar-bangla")
                        return (f, 1)
                    }
                    // (A run of Bengali characters with no letter (digits, signs, marks), in a face Windows lacks (Nikosh, Kalpurush...): Word draws it in Nirmala UI, so the digits take
                    // Nirmala's own advances from the table; 2263e221's "\u{9EE}" is 8.35 pt in Word, 6.5 in the stand-in.)
                    if text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF }),
                       !text.unicodeScalars.contains(where: { ($0.value < 0x980 && $0.value >= 0x900 && $0.value != 0x964 && $0.value != 0x965) || $0.value >= 0xA00 && RichLayout._isIndic($0.value) }),
                       !["mangal", "kokila", "aparajita", "raavi", "shruti", "gautami", "vrinda", "utsaah", "shonar bangla", "kalimati", "latha", "vijaya"].contains(
                        (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()),
                       RichLayout._bengaliMissingFace((run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased(), document) != "shonar bangla" {
                        RuleTrace.hit("word-bengali-digits-only-run-in-a-missing-face-is-nirmala")
                        return ("nirmala ui", 1)
                    }
                    // (A run of only a danda in a missing face, in a paragraph of Devanagari or Bengali: Word draws it in Nirmala UI, 3.89 pt at 9 pt, where the
                    // stand-in's Bengali danda is 3.41; lab dnd1: the lone "।" stays on line 2 in ours at indent 0 where Word's wraps it.)
                    if text.unicodeScalars.contains(where: { $0.value == 0x964 || $0.value == 0x965 }),
                       !text.unicodeScalars.contains(where: { $0.value != 0x964 && $0.value != 0x965 && $0.value != 0x20 }),
                       p.text.unicodeScalars.contains(where: { $0.properties.isAlphabetic && ($0.value >= 0x900 && $0.value <= 0x97F) }),
                       !p.text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF }),
                       !["mangal", "kokila", "aparajita", "raavi", "shruti", "gautami", "vrinda", "utsaah", "shonar bangla", "kohinoor bangla", "kalimati", "latha", "vijaya"].contains(
                        (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()) {
                        RuleTrace.hit("word-danda-only-run-in-a-missing-face-is-nirmala")
                        return ("nirmala ui", 1)
                    }
                    // (A run of only a danda in a missing Bengali face (Nikosh, SolaimanLipi) inside a paragraph of Bengali letters: Word draws it in Mangal, 4.58 pt at 11 pt
                    // (0.4166 em) where the stand-in's Bengali danda is 4.1; dx2 2263e221 "\u{9E9}\u{964} ব্যবসায় নিবন্ধন নম্বর": "নম্বর" wraps in Word, stays in ours.)
                    if text.unicodeScalars.contains(where: { $0.value == 0x964 }),
                       !text.unicodeScalars.contains(where: { $0.value != 0x964 && $0.value != 0x20 }),
                       RichLayout._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") != nil,
                       p.text.unicodeScalars.contains(where: { $0.properties.isAlphabetic && $0.value >= 0x980 && $0.value <= 0x9FF }) {
                        RuleTrace.hit("word-danda-only-run-in-a-missing-bengali-face-is-mangal")
                        return ("mangal", 1)
                    }
                    // (A run of spaces and tabs in a missing Bengali face (Nikosh, SolaimanLipi) inside a paragraph of Bengali letters: Word draws the spaces in Mangal
                    // but they do not raise the line, which stays Nirmala UI's 1.33 em: dx2 2263e221's bold heading, 14.6 pt apart in Word, 18.5 in ours.)
                    if !text.isEmpty, !text.unicodeScalars.contains(where: { $0.value != 0x20 && $0.value != 0x09 }),
                       RichLayout._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") != nil
                        || (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "siyam rupali",
                       p.text.unicodeScalars.contains(where: { $0.properties.isAlphabetic && $0.value >= 0x980 && $0.value <= 0x9FF }),
                       !p.text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF && !$0.properties.isAlphabetic && $0.properties.generalCategory != .nonspacingMark && $0.properties.generalCategory != .spacingMark }) {
                        RuleTrace.hit("word-spaces-in-a-missing-bengali-face-keep-the-nirmala-line")
                        return ("nirmala ui", 1)
                    }
                    if let named = _namedMetricFace(run, named, document, text) {
                        RuleTrace.hit("word-run-with-no-indic-letters-takes-the-line-of-the-face-it-names")
                        return (named, 1)
                    }
                    // (Word's print of dx2 e86e26f7: spaces, commas, brackets and digits that fall back to Malgun inside a Bengali line do not raise it, a
                    // Bengali-only line stays at Nirmala's 13.3 pt; a run holding Latin letters still does.)
                    if malgunLatin,
                       text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 && !($0.value < 0x80 && !(($0.value | 0x20) >= 0x61 && ($0.value | 0x20) <= 0x7A)) })
                        || !p.text.unicodeScalars.contains(where: { RichLayout._isIndic($0.value) }) && text.unicodeScalars.contains(where: { $0.value == 0x20 }) {
                        RuleTrace.hit("word-malgun-alternate-latin-run-is-malgun-line")
                        return ("malgun gothic", 1)
                    }
                    if aumsLatin, text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 }) {
                        RuleTrace.hit("word-aums-latin-run-is-a-yu-gothic-line")
                        return ("yu gothic", 1)
                    }
                    if aumsYuInIndic, text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x7F }) {
                        RuleTrace.hit("word-aums-latin-run-in-indic-paragraph-is-a-yu-gothic-line")
                        return ("yu gothic", 1)
                    }
                    if utsaahLatin,
                       (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "utsaah" {
                        return ("utsaah", 1)
                    }
                    return nil
                }
                let all = count.values.reduce(0, +)
                let cs = (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
                let bold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
                // Which face: the complex-script one where Windows has it; a face it lacks (Arial, Times, Kalpurush, Nikosh, Arial Unicode MS...)
                // Word draws in Nirmala UI, but Kalimati (Devanagari) in Mangal, and a Bengali face whose font-table signature is Bengali-only in Shonar Bangla
                // (labs bnfield: the signature decides, not name, panose, charset or alternate; dx2 prints).
                var face = cs
                switch cs {
                case "kalimati": face = "mangal"
                case "mangal", "kokila", "aparajita", "raavi", "shruti", "gautami", "vrinda", "utsaah", "shonar bangla": break
                // A Gurmukhi run whose complex face is Times New Roman is drawn in Raavi, not Nirmala UI, once an earlier run of the document names Raavi (labs punjabi-raavi; dx2 53342b69 against 60aa1e5d)
                case "times new roman" where top.key == "P" && run.gurmukhiRaavi: face = "raavi"
                default: face = top.key == "B" ? RichLayout._bengaliMissingFace(cs, document) : (document.devanagariFirstRunMangal && cs != "times new roman" ? "mangal" : "nirmala ui")
                }
                guard var scale = RichLayout._indicScale[face]?[top.key] else { return nil }
                if face == "nirmala ui", bold { scale *= 1.076 / 1.086 }
                // Shruti Bold runs 4% narrower than Shruti: dx2 16200736's heading, word starts 111.0 pt apart in Word, 115.9 in ours.
                if face == "shruti", bold { scale *= 0.958 }
                return (face, all * 2 >= letters ? scale : 1)
            }()
            // (A zero-width character the layout puts in — a break the
            // engine would not make, or a joiner — in the Latin kind's
            // style whatever the text around it: in the East Asian style
            // its glyph is the Latin base family's, whose ascent and
            // descent split the em otherwise than the CJK face's, and a
            // line with both grew 0.9pt at 12pt — zh-799c91cd's held
            // spaces, and every line with a break before a quote.)
            // (With none of the run's spacing: a run spaced 0.6pt gave
            // each break it holds 0.6pt the fitter does not count, and
            // zh-b00fef0d's "…改革决策部署" lost "署" to the next line.)
            // (Nor any height: it sets no line, as a space sets none beside
            // other text. zh-7773163d's p38 paragraph, a 17pt "一、" head
            // over 16pt text (no strut, two sizes), took the Latin face's
            // deeper descent from its joiners, and its lines stood 24.6pt
            // apart where Word's print has 23.0. Except in a math face's
            // run, whose letters are set at 0.6 of its line to keep the
            // platform math face's split out of it: there the joiners are
            // what gives the line Cambria Math's 1.17 em, bug59058's
            // formula lines 15.24pt apart as in Word's print, 15.0 without.)
            // (Arabic set to the original face's joining widths, word by
            // word — it parts only at spaces: each word its own span, drawn
            // condensed or widened to the width its joining forms have in
            // that face (`RichResolvedFace.joinedAdvances`), which the line
            // breaking then measures too. Spacing would split a joined
            // word's shaping or, on a zero-width character, be measured and
            // not drawn right to left — zh-d97c5474's lines broke as Word's
            // and stood 47pt past the margin — and on the spaces it ran the
            // words together, Noto Naskh being 11% wider than Arial.)
            complexFaceOfRun = {
                guard theme.wordRules else { return nil }
                let normal = _normalChar(document)
                let latin: String? = run.fontFamily ?? named?.char.fontFamily ?? normal?.fontFamily ?? theme.fontFamily
                let complex: String? = run.complexFontFamily ?? named?.char.complexFontFamily ?? normal?.complexFontFamily
                // (No complex-script face named, and Arial Narrow for Latin: Word sets the Arabic in Arial, not in the narrow face.)
                var name = complex ?? latin
                if complex == nil, name?.trimmingWhitespace().lowercased() == "arial narrow" { name = "Arial" }
                return theme.complexFace(name, latin: latin, letters: run.csLetters)
            }()
            // (A slide's Arabic in a face that carries its own shaped advances, Traditional Arabic or Sakkal Majalla: set word by word at
            // them as Word's is.)
            joinedFace = run.rightToLeft ? complexFaceOfRun : (theme.wordRules || !p.style.rightToLeft ? nil : run.fontFamily.flatMap { theme.faceResolver?($0, false) }.flatMap { $0.joinedAdvances != nil ? $0 : nil })
            // A right-to-left space is set in the complex-script face when the document names one apart from the Latin face (b514c2: Arial against the theme's Aptos); the same name for both keeps the Latin table (dx2 Tahoma fa/ur docs).
            complexSpaceFace = {
                guard let joinedFace else { return nil }
                let normal = _normalChar(document)
                let latin = (run.fontFamily ?? named?.char.fontFamily ?? normal?.fontFamily ?? theme.fontFamily)?.trimmingWhitespace().lowercased()
                guard let complex = (run.complexFontFamily ?? named?.char.complexFontFamily ?? normal?.complexFontFamily)?.trimmingWhitespace().lowercased(), complex != latin else { return nil }
                return joinedFace
            }()
            // (A zero-width non-joiner stays inside the word: Word sets the
            // two parts as two joined words and the mark at no width, where
            // the stand-in gave it 3pt and the parts no scale — lo
            // tdf163575's "می‌توان" 37pt to Word's 27.)
            notoStyle = nil
            segoeStyle = nil
            devanagariStyles = [:]
            spans = []
            start = text.startIndex
            current = nil
            offset = base
            i = text.startIndex
            compatJoinerAfter = nil
            // (Measured as shown: a run in capitals (`capped`) is spaced,
            // kerned and put on the grid by its capitals — 60810's titles,
            // "Connection to global talent programmes/R200" in caps, lost
            // "TA" and "LT"'s kerning and wrapped a line PowerPoint fits.)
            shownCaps = theme.measuresShownCaps && (run.caps || ((named?.char.caps ?? false) && !run.off.contains(.caps)))
            // (A raised or lowered run's line is its whole size's, unshifted,
            // as if it were not raised: lab `sup` (macOS-doc, Word for Mac)
            // — a 12pt 宋体 line with a 10pt YaHei superscript is 17.28pt
            // in Word, as with it plain (17.04), ours 15.57; a footnote's
            // mark the same; zh-7654804a's rows of "105" and a superscript
            // "註3" stand 3pt taller in Word's print. Its glyphs are drawn
            // shrunk and shifted; a zero-width non-joiner of its whole
            // size holds the line — part of what stands before it to the
            // line breaking, where a word joiner kept zh-424775e4's note mark
            // from opening a line after "韩国。" as Word's print has it.)
            // (Only where that line is taller than the rest of the paragraph's:
            // a Times note mark in YaHei text changes nothing, and its joiner
            // only stirred the line fitting.)
            // (Not in a line with a page number's field: its raised "/" grows the line by 1.08pt at
            // 15.5pt on 10, not by the whole size's 6.3 — lab pgf, Word for Windows, lo-198cd200's footer.)
            if theme.wordRules, run.script != .normal, NativeParagraphBuilder.supportsBaselineShift, let first = text.first,
               !p.runs.contains(where: { $0.style.field != nil && $0.style.fieldResult != nil && $0.style.script == .normal }),
               let ownLine = theme.naturalLine(for: { var w = run; w.script = .normal; return w }(), named: named, eastAsian: RichLayout.isEastAsian(first, hinted: hinted)),
               ownLine > ({ () -> Double in
                   var most = 0.0, at = 0
                   let units = Array(p.text.utf16)
                   for r in p.runs {
                       defer { at += r.length }
                       guard r.style.script == .normal, r.length > 0, at + r.length <= units.count else { continue }
                       let part = String(decoding: units[at ..< at + r.length], as: UTF16.self)
                       let rh = (r.style.fontHint ?? named?.char.fontHint) == "eastAsia"
                       let hasEA = part.contains { RichLayout.isEastAsian($0, hinted: rh) }
                       let hasLatin = part.contains { !RichLayout.isEastAsian($0, hinted: rh) && !$0.isWhitespace }
                       if hasEA { most = max(most, theme.naturalLine(for: r.style, named: named, eastAsian: true) ?? 0) }
                       if hasLatin { most = max(most, theme.naturalLine(for: r.style, named: named, eastAsian: false) ?? 0) }
                   }
                   return most
               }()) + 0.01 {
                var whole = run
                whole.script = .normal
                let s = theme.textStyle(for: whole, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                        eastAsian: RichLayout.isEastAsian(first, hinted: hinted), gridPitch: pitch, scriptHidden: true)
                // (No width of its own: shaped alone, as it is set, it has
                // one, and a line at its limit took a character less.)
                let alone = TextPainter(text: TextSpan(text: "\u{200C}", style: s), textDirection: .ltr)
                alone.layout(minWidth: 0, maxWidth: 100_000)
                let own = alone.width
                alone.dispose()
                spans.append(TextSpan(text: "\u{200C}", style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) - own)))
                ctx.inserts.append(offset)
            }
            while i < text.endIndex {
                ch = shown(text[i])
                after = text.index(after: i)
                following = (after < text.endIndex ? text[after] : next).map(shown)
                // (An ideographic space on a line of spaces alone is set
                // as the mark is, in the run's Latin face: see `lineSize`.)
                ea = theme.wordRules && RichLayout.isEastAsian(ch, hinted: hinted || (eastDash && ch == "\u{2014}")) && !(ch == "\u{3000}" && lineSize?.blank == true)
                    && !(latinDash && ch == "\u{2013}")
                    // (Nor a "×" or "÷", Latin-1's signs, which Word sets in the hAnsi
                    // face as it does the dash: zh-7a16a243's unhinted "×" in a run of
                    // 標楷體 over its heading style's Arial hAnsi is Arial's 9.34pt and
                    // half the grid's 1.0076 in Word for Windows' print, 9.9 — ours set
                    // 標楷體's half em, 8.5, and the line "…672％)，然上開「允建樓地板面"
                    // took the "積" Word sends down.)
                    && !(latinDash && RichTextTheme.wordWindowsPages && (ch == "\u{00D7}" || ch == "\u{00F7}"))
                kind = ea ? -1 : (classed ? RichResolvedFace.characterClass(ch) : 0)
                // (Circles, squares and stars in an East Asian run are the East Asian face's glyph
                // — an em wide, 0.86 across — not the Latin stand-in's small one: kind -4.)
                if hyphenFace != nil, ch == "-" { kind = -1000 }
                if ea, eastDash, ch == "\u{2014}" { kind = -5; RuleTrace.hit("word-em-dash-drawn-in-east-asian-hansi-face") }
                if ea, theme.wordRules, RichTextTheme.wordWindowsPages, RichLayout._cjkFaceFamily != nil, let u = ch.unicodeScalars.first?.value,
                   (0x25A0 ... 0x25EF).contains(u) || u == 0x2605 || u == 0x2606 { kind = -4 }
                // (A card suit in a run (East Asian by its hint) whose Latin face is Malgun Gothic itself (a theme's; Nanum Barun's suits are not an em: b60ada18) is that face's glyph, an em wide, not
                // the stand-in's 0.66 em: xd 89a3482a's "♣♣♣" are Malgun 12 pt wide each in the print, ours 7.9, and "수" after them stayed on the line.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, RichLayout._cjkFaceFamily != nil,
                   let u = ch.unicodeScalars.first?.value, (0x2660 ... 0x2667).contains(u),
                   { () -> Bool in
                       let fam: String = run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily ?? ""
                       return ["맑은 고딕", "malgun gothic"].contains(fam.trimmingWhitespace().lowercased())
                   }() {
                    kind = -4
                    RuleTrace.hit("word-card-suit-in-a-korean-latin-face-is-an-em")
                }
                // (A curly quote an embedded subset lacks is Word's fallback face's too, full width:
                // zh-5450d509's “ ” after 仿宋_GB2312's five glyphs are JhengHei's 12pt in the
                // print; ours set them as a missing glyph, 17.8 and 12.1, and a line lost a character.)
                if ea, let (_, covers) = uncovered, let u = ch.unicodeScalars.first?.value, u >= 0x2E80 || (RichTextTheme.wordWindowsPages && ((0x2018 ... 0x201D).contains(u) || (0x2460 ... 0x2473).contains(u))) {
                    if covers.contains(u) { chainAt = nil }
                    else if let chain {
                        if let at = chainAt, chain[at].covers?.contains(u) ?? true {
                            kind = -10 - at
                        } else if chainAt == nil, let w = RichLayout._cambriaMathOpeners[u] {
                            // (A symbol that opens a stretch is Cambria Math's,
                            // at its own width, on no line of its own: every
                            // "〔", "〕" and circled number so placed in word-win
                            // — zh-92373179's 31 "①"… at a line's start or after
                            // a held character, 1.19 em at its grid; zh-540dc149,
                            // zh-5450d509, zh-c2f6d17a, zh-e68a2f57's brackets
                            // after a digit. One after a fallen-back character
                            // keeps that one's face.)
                            kind = -9
                            cambriaWidth = w
                        } else {
                            chainAt = chain.firstIndex { $0.covers?.contains(u) ?? true } ?? chain.count - 1
                            kind = -10 - chainAt!
                        }
                    } else { kind = -3 }
                } else if chain != nil, !ch.isWhitespace {
                    // (Any other character seen ends a stretch — a digit as
                    // a held ideograph does: with that, all of the three
                    // prints' 13,171 fallen-back characters are so.)
                    chainAt = nil
                }
                // The spaces that end a paragraph after ideographs, in a run
                // whose Latin letters stand in for an East Asian face's
                // own, take the ideographs' face, at the stand-in's width
                // (kind -2): set in the stand-in, its other ascent and
                // descent made the line taller than either face. The Mac's
                // lab `hfl` (Word 16): five spaces after "红河县人民政府发布"
                // in 14pt bold 宋体 make the paragraph no taller; ours stood
                // 1.2pt taller on Linux, and zh-1563bd74's footer took a
                // line off a page. (Spaces within the line are left in the
                // stand-in: set in the ideographs' face, the line fitting
                // measured them otherwise, and lines parted elsewhere.)
                if theme.wordRules, ch == " ", ctx.afterIdeograph, offset >= trailingSpaces, latinFace?.isEastAsian == true { kind = -2 }
                if ea { ctx.afterIdeograph = true } else if ch != " " { ctx.afterIdeograph = false }
                // A stretch of Latin characters with no space in it is
                // one word to Word, which parts it only after a hyphen:
                // an address, a date with strokes, "100%200%", "(a)(b)"
                // go to the next line whole. The engine would break
                // after the stroke, the question mark, the percent
                // sign and the bracket; a word joiner holds them.
                // (One too long for any line Word parts wherever the
                // line ends, starting where it stands: a zero-width
                // space before each of its characters.)
                if ch != "." { ctx.dotsAttached = false } else if ctx.before != "." { ctx.dotsAttached = ctx.before.map { b in
                    // (Thai, Lao, Myanmar and Khmer are broken by dictionary, not by the letters' class: xd's Thai forms part their stops.)
                    let v = b.unicodeScalars.first?.value ?? 0
                    return (b.isLetter || b.isNumber || (b.unicodeScalars.first?.properties.generalCategory).map({ [.nonspacingMark, .spacingMark].contains($0) }) == true || b == ":") && !(v >= 0xE00 && v <= 0xEFF) && !(v >= 0x1000 && v <= 0x109F) && !(v >= 0x1780 && v <= 0x17FF)
                } ?? false }
                _sblk0()
                // (Right-to-left digits: Word for Windows keeps "-", "/" and "%"
                // from joining the numbers round them, as the Unicode rules
                // would for "10-18/11" and "50%": each number stands whole and
                // the whole reads right to left, "11/18-10" and "%50" on the
                // page, while ":", "," and "." join as written. Lab bidi-digits,
                // Latin digits (Arabic-Indic ones the engine's own order already splits, and an
                // extra mark there only cost dx2 ur 968500c3 a point), a bidi paragraph or not, in a
                // table or not; not where the run's complex-script language is Persian. A right-to-left mark before the sign and before
                // what follows it gives that.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, wasRightToLeft, offset > 0 {
                    func digit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
                    func sign(_ c: Character) -> Bool { c == "-" || c == "/" || c == "%" }
                    if (sign(ch) && ctx.before.map(digit) == true) || (digit(ch) && ctx.before.map(sign) == true) {
                        flush(i)
                        spans.append(TextSpan(text: "\u{200F}", style: zeroWidth(current ?? kind)))
                        ctx.inserts.append(offset)
                    }
                }
                // (A distributed line's room before this character: a word
                // joiner that wide. Spacing on the character itself would
                // be set half before it, and move the line's first.)
                if let g = ctx.spread[offset], g > 0 || (g < 0 && ch == " ") {
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: style(kind).copyWith(letterSpacing: g)))
                    ctx.inserts.append(offset)
                }
                // In East Asian text a curly quote is a full-width mark,
                // an em with the blank half outside it, as 宋体 and
                // every face Word sets such text in draw it; the faces
                // that stand in here draw the Latin one. The closing
                // one's blank is spacing after it.
                // A CJK compatibility ideograph Word on a Mac sets in Noto
                // Sans SC — its East Asian face has none, and its fallback
                // takes that face for these (`_notoCompatibility`) and
                // Heiti SC for the rest — gives its line Noto's height: a
                // word joiner in that face before it. Lab `cj2` (Word 16,
                // 標楷體 → YaHei 12pt, 2026-10-15): a line holding "行"
                // U+FA08 stands 1.44pt lower under the line above and
                // 0.48 higher over the next; one holding "零" U+F9B2, in
                // Heiti, is as any. zh-8e8d4c40's page 5 ran a line long.
                if theme.wordRules, ea, let u = ch.unicodeScalars.first?.value, u >= 0xF900, u <= 0xFAFF,
                   RichLayout._notoCompatibility.contains(u),
                   theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                       ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.lacksCompatibilityIdeographs == true {
                    flush(i)
                    if notoStyle == nil {
                        var r = run
                        r.eastAsiaFontFamily = "Noto Sans SC"
                        notoStyle = theme.textStyle(for: r, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                                    eastAsian: true, gridPitch: pitch, scriptHidden: true)
                        // (Noto's line over and under the baseline, not
                        // its height shared out as the joiner's own face
                        // shares its ascent and descent: zh-8e8d4c40's
                        // lines holding "狀" and "行" stood 2.6pt under
                        // the line above, Word's 1.4, and no deeper.)
                        if let joiner = _notoJoiner(r, notoStyle!, run, named, style(kind), p.style, pitch, scale) { notoStyle = joiner }
                    }
                    // (A joiner keeps the line from parting before the
                    // character: a zero-width space before it gives the
                    // break back, the joiner going on with the character.
                    // zh-5b7ae054's "…基本抗災能力" ends its line at "能" in
                    // Word's print, "力" U+F98A opening the next; ours
                    // carried "能力" over and lost a character a line.)
                    // (After a Latin letter, a digit or a Latin closer too:
                    // zh-72da925e's "…經行政院於79年" ends a line "於79" in
                    // Word's print, "年" U+F98E opening the next; the joiner
                    // held "79年" whole and ours ended the line "於".)
                    if let b = ctx.before, RichLayout.isEastAsian(b, hinted: true) ? !RichLayout._openingMarks.contains(b)
                        : b.isASCII && (b.isLetter || b.isNumber || ")]}%.,;:!?".contains(b)) {
                        spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                        ctx.inserts.append(offset)
                    }
                    spans.append(TextSpan(text: "\u{2060}", style: notoStyle!))
                    ctx.inserts.append(offset)
                }
                // A shape Word sets in the run's Latin face (no East Asian
                // hint), which has none, and its fallback in Segoe UI Symbol,
                // gives its line that face's ascent and descent (its hhea,
                // 2210 and 514 of 2048): a joiner sized so before it. Lab
                // `picln` (the Mac 7bd18d8e, Word 16, zh-e68a2f57's package):
                // its 9pt note, 楷体_GB2312 over Times New Roman, holding "◎"
                // stands 0.48pt lower under the line above, 0.96 at 12pt, at
                // single and 1.1 lines alike — its embedded 楷体 has the
                // glyph; "◇◆★☆" as "◎", "●□▲○■※" (Times has them) and
                // "①△" (Cambria Math) nothing. Ours drew them in YaHei, its
                // line as any, and p7's third note line stayed on the page.
                @inline(never) func _r1() {
                if latinShapes, let u = ch.unicodeScalars.first?.value, RichTextTheme.segoeSymbolShapes.contains(u) {
                    flush(i)
                    if segoeStyle == nil { segoeStyle = _segoeJoiner(run, named, style(-1), p.style, pitch, scale) }
                    if let joiner = segoeStyle {
                        // (Its break before kept: see the Noto joiner's.)
                        if let b = ctx.before, RichLayout.isEastAsian(b, hinted: true) ? !RichLayout._openingMarks.contains(b)
                            : b.isASCII && (b.isLetter || b.isNumber || ")]}%.,;:!?".contains(b)) {
                            spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                            ctx.inserts.append(offset)
                        }
                        spans.append(TextSpan(text: "\u{2060}", style: joiner))
                        ctx.inserts.append(offset)
                    }
                }
                }
                _r1()
                // (A word of Devanagari or Bengali, set in the face Word draws it in, gives its line that face's height, not
                // the Latin face's: a joiner in its ascent and descent before the word. hin-z19439612's 12pt Mangal lines
                // step 23.2 in Word's print (1.680 em at 1.15 lines), ours 15.9. Which face: the run's complex-script one where
                // Windows has it (Mangal; Kokila only in italic); the rest, Kokila regular and bold and Kalpurush, Word draws in
                // Nirmala UI — hin-z18479909's 9942 regular Devanagari and ben-z17281487's Bengali are Nirmala in its prints.)
                // (A Hangul-named Latin face Word's box lacks, with no font-table entry (22de7d's theme face 함초롬돋움): Word draws the Latin letters
                // and digits in Yu Gothic and the Hangul in Malgun Gothic, so a line holding one takes Yu Gothic's deeper descent: 19.2 pt steps at 10 pt
                // against 18.5. Each face drawn on a line feeds its own ascent and descent into the line's max.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, u >= 0x20, u < 0x250, ch.unicodeScalars.count == 1, !RichLayout._setsNoLine(ch), ch != " ", ch != "\u{A0}",
                   !(ctx.before.map { ($0.unicodeScalars.first?.value ?? 0x3000) < 0x250 && !($0 == " " && ctx.beforeBefore == nil) } ?? false), _yuLatinOfMissingHangulFace(run, named, document), !document.hasIndicText, !aumsLatin {
                    if devanagariStyles["missingHangulYu"] == nil {
                        devanagariStyles["missingHangulYu"] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: RichLayout._indicLines["malgun gothic"]!.0, descent: 0.492)?.copyWith(debugLabel: "yu-joiner")
                    }
                    if let joiner = devanagariStyles["missingHangulYu"] ?? nil {
                        RuleTrace.hit("word-missing-hangul-face-latin-is-yu-gothic-descent")
                        flush(i)
                        spans.append(TextSpan(text: "\u{2060}", style: joiner))
                        ctx.inserts.append(offset)
                    }
                }
                // (The won sign in a run whose Latin face is a Korean one with no ₩ of its own, set under no East Asian hint: Word for Windows
                // draws it in Malgun Gothic, so its line takes Malgun's height, 1.730 em. xd b6f6c7d4 p3: "(₩58,125,000,000)" in 12pt 한양신명조
                // at 1.75 lines, its line stands 3.4pt deeper than a Batang one, as ❏'s in Segoe UI Symbol.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, ch == "\u{20A9}", run.fontHint != "eastAsia",
                   theme.faceResolver?(run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false)?.isEastAsian == true,
                   let metrics = RichLayout._indicLines["malgun gothic"] {
                    if devanagariStyles["wonMalgun"] == nil {
                        devanagariStyles["wonMalgun"] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: metrics.0, descent: metrics.1)
                    }
                    if let joiner = devanagariStyles["wonMalgun"] ?? nil {
                        RuleTrace.hit("word-won-sign-in-korean-latin-face-is-malgun-height")
                        flush(i)
                        spans.append(TextSpan(text: "\u{2060}", style: joiner))
                        ctx.inserts.append(offset)
                    }
                }
                // (Tamil set in Noto Sans Tamil, a face Windows lacks: Word draws the letters in Nirmala UI but every digit, mark and Latin
                // letter in Mangal, so a line holding one is Mangal's 1.680 em tall; a line of Tamil letters and spaces stays Nirmala's 1.33.
                // xd c016493b: pitches 20.2 with a mark, 17.9 and 18.2 beside such a line, 16.0 without.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, !RichLayout._isIndic(u) || u == 0x964 || u == 0x965,
                   !ch.isWhitespace,
                   u != 0x200B, u != 0x200C, u != 0x200D, u != 0x2060, u != 0xFFFC,
                   !(ctx.before.map { !$0.isWhitespace && !($0.unicodeScalars.first.map { RichLayout._isIndic($0.value) } ?? false) } ?? false),
                   RichLayout._markInMangal(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "", text) || ((_isSolaimanLipi(run, named, document) || (ctx.splittingMark && p.style.lineSpacing > 1.0 && p.style.lineHeightPoints == nil)) && _asciiRunInMissingBengaliFace(run, named, document, text, p.text)),
                   let metrics = RichLayout._indicLines["mangal"] {
                    if devanagariStyles["mangal"] == nil {
                        devanagariStyles["mangal"] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: metrics.0, descent: metrics.1)
                    }
                    if let joiner = devanagariStyles["mangal"] ?? nil {
                        flush(i)
                        // (After a space the joiner would glue the mark to it and lose the break there: a break opportunity, as the digit rule below keeps.)
                        if ctx.before?.isWhitespace == true, _asciiRunInMissingBengaliFace(run, named, document, text, p.text) {
                            spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                            ctx.inserts.append(offset)
                        }
                        spans.append(TextSpan(text: "\u{2060}", style: joiner))
                        ctx.inserts.append(offset)
                    }
                }
                // (A run that names Mangal and holds no Devanagari letter, digits and signs, still sets the line at Mangal's tall 18.5 pt (11 pt) in
                // Word's print, in a paragraph with no Indic letter at all (one with Devanagari already has the joiner; adding it there broke dx2 254ca33b, 375919ba): dx2 2db27e2d's "• 4(99)" bullets step 26.5 pt (8 before + 18.5), ours 20.7 on the Times line.)
                if namedFace == "mangal", theme.wordRules, RichTextTheme.wordWindowsPages, !p.text.unicodeScalars.contains(where: { RichLayout._isIndic($0.value) }), let u = ch.unicodeScalars.first?.value, !RichLayout._isIndic(u), !ch.isWhitespace,
                   u != 0x200B, u != 0x200C, u != 0x200D, u != 0x2060, u != 0xFFFC,
                   !(ctx.before.map { !$0.isWhitespace } ?? false),
                   let metrics = RichLayout._indicLines["mangal"] {
                    if devanagariStyles["mangal"] == nil {
                        devanagariStyles["mangal"] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: metrics.0, descent: metrics.1)
                    }
                    if let joiner = devanagariStyles["mangal"] ?? nil {
                        RuleTrace.hit("word-mangal-named-digit-run-sets-the-mangal-line-without-devanagari")
                        flush(i)
                        if let before = ctx.before, before.isWhitespace {
                            spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                            ctx.inserts.append(offset)
                        }
                        spans.append(TextSpan(text: "\u{2060}", style: joiner))
                        ctx.inserts.append(offset)
                    }
                }
                // (A missing Korean face Word sets in Batang takes its quotes, circles, circled digits and middle dot from Malgun
                // Gothic, and a line holding one is Malgun's height: 6a68f6ca's lines step 29.9 into one, 31.9 out of one and 35.3
                // between two at 1.7 lines, 26.6 between plain ones. The split is Malgun's 1.175 + 0.557 against Batang's 1.009 + 0.291.)
                // (A run that names the East Asian face and hints East Asian draws its symbols in Batang, no Malgun: 218dff52's "7. ... △△△" lines step 31.2 as plain ones.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, ch.unicodeScalars.count == 1,
                   !(run.eastAsiaFontFamily != nil && (run.fontHint ?? named?.char.fontHint) == "eastAsia"),
                   (u >= 0x25A0 && u <= 0x25FF) || u == 0xB7 || (u >= 0x2460 && u <= 0x2469) || u == 0x203B || u == 0x2192
                    || u == 0x2018 || u == 0x2019 || u == 0x201C || u == 0x201D || u == 0xB1 && run.loneQuote,
                   theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                       ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.malgunSymbols == true
                    // (A run that names only the ascii face, the missing Korean one, still draws △ and ○ in it (they have no ascii form; quotes in such a run stay Latin: 218dff52 page 2): 218dff52's △△△.)
                    || (u >= 0x25A0 && u <= 0x25FF) && (run.eastAsiaFontFamily == nil && run.fontFamily.map { theme.faceResolver?($0, true)?.malgunSymbols == true || ($0.trimmingWhitespace() == "굴림" && u >= 0x25A0 && u <= 0x25FF) } == true)
                    // (A run holding only a middle dot, set in Gulim, is drawn in Malgun Gothic too: xd ac5ff286's "유치·운영" line, whose dot run Word's print names
                    // MalgunGothic, stands 29 and 30 pt from its neighbours where plain Gulim lines are 25.)
                    || u == 0xB7 && run.loneDot && ["굴림", "gulim"].contains((run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? run.fontFamily ?? "").lowercased())
                    // (A curly quote that is a run of its own has no Hangul neighbour to take its face from, so Word draws it in the hAnsi face: Malgun Gothic
                    // when the theme's minor font is, though ascii and eastAsia say Gulim. xd b6f6c7d4's speech "의안명 “병 제조용 PET CHIP 구매”"
                    // prints its quotes in MalgunGothic and the line steps 29.8 pt, plain Gulim lines 25; kor-z191's lone ” names hAnsi Gulim and stays Gulim.)
                    || (u == 0x2018 || u == 0x2019 || u == 0x201C || u == 0x201D || u == 0xB1) && run.loneQuote && !run.hAnsiNamedAsAscii && ["굴림", "gulim"].contains((run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? run.fontFamily ?? "").trimmingWhitespace().lowercased()) && ["맑은 고딕", "malgun gothic"].contains((_normalChar(document)?.hAnsiFontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()) {
                    RuleTrace.hit("lone-middle-dot-in-gulim-is-malgun-line")
                    if devanagariStyles["malgunKo"] == nil {
                        // (Word's lab kr-sym, 12 pt Batang lines at 1.0, 1.75 and 3.0: a Malgun symbol line is Malgun's own 1.288 + 0.441 em times the multiple
                        // (steps into / out of the line 30.7 / 32.9 at 1.75, 50.3 / 58.8 at 3.0; 6a68f6ca's 29.9 / 31.9 at 1.7); the joiner is the box, the
                        // first-line raise places the baseline.)
                        let malgun = RichLayout._indicLines["malgun gothic"] ?? (1.288, 0.442)
                        devanagariStyles["malgunKo"] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: malgun.0, descent: malgun.1, evenExtra: true)
                    }
                    if let joiner = devanagariStyles["malgunKo"] ?? nil {
                        flush(i)
                        spans.append(TextSpan(text: "\u{2060}", style: joiner))
                        ctx.inserts.append(offset)
                    }
                }
                // (The CJK compatibility forms U+FE30-FE5F in MS Mincho/MS Gothic text are not in those faces: Word draws them in Yu Gothic (the
                // vertical brackets and the small parentheses/brackets/braces) or Microsoft JhengHei (the small comma and ideographic comma), so a
                // line holding one is that face's, taller than the Mincho line: xb 5dc87fc7 p4, a 44.1 pt block where ours was 39.7.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, (0xFE30 ... 0xFE5F).contains(u),
                   let fb = RichLayout._compatFormFallbackLine(u),
                   { let n = (run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily ?? "").lowercased()
                       return n.containsSubstring("ms mincho") || n.containsSubstring("ms gothic") }() {
                    let key = "compatForm\(fb.0)"
                    if devanagariStyles[key] == nil {
                        devanagariStyles[key] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: fb.1.0, descent: fb.1.1)
                    }
                    if let joiner = devanagariStyles[key] ?? nil {
                        // (After the form, so a line that starts with it holds the taller face and the line it leaves does not: xb 5dc87fc7 p5.)
                        compatJoinerAfter = joiner
                    }
                }
                // (A Devanagari word wider than its column is cut where each line fills, and every line of it is a line of Mangal: the joiner
                // that sets that line stands inside the word too, at each letter that opens a cluster. dx2 9baed400's 40 pt Kalimati cell, 21.2 pt
                // pitch in Word on every line, 17.6 on the lines ours began mid-word.)
                insideWide = !wideIndicWords.isEmpty && wideIndicWords.contains { offset > $0.lowerBound && offset < $0.upperBound }
                // (Myanmar: the line joiner goes before each consonant, so every line that holds Myanmar letters has Myanmar Text's line.)
                myanmarJoin = indic?.face == "myanmar text" && (ch.unicodeScalars.first.map { $0.value >= 0x1000 && $0.value <= 0x1021 } ?? false)
                if theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, RichLayout._isIndic(u) || myanmarJoin,
                   myanmarJoin || insideWide || !(ctx.before?.unicodeScalars.first.map { RichLayout._isIndic($0.value) || $0.value == 0x200D || $0.value == 0x200C } ?? false) {
                    let face0 = indic?.face
                    // (Shonar Bangla Bold is its own face in Word: 1721+978 of 2048 against the regular's 1655+996.)
                    let face = (face0 == "shonar bangla" && (run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold)))) ? "shonar bangla bold" : face0
                    if let face, let metrics = RichLayout._indicLines[face] {
                        if devanagariStyles[face] == nil {
                            devanagariStyles[face] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: metrics.0, descent: metrics.1, belowOnly: face == "kokila" || face.hasPrefix("shonar bangla"))
                        }
                        if let joiner = devanagariStyles[face] ?? nil {
                            flush(i)
                            // (A zero-width space before it gives the break the joiner would forbid back: after a space the word
                            // would not part from the line, and the engine cut words inside.)
                            // (Not after an opening bracket or quote: Word keeps "(श्रमदिन)" whole, and the space let the line end on the "(": 9baed400's header cell.)
                            // (Nor after a slash: Word keeps a chunk like "hau/poli" whole when it fits, and parts at the slash only a chunk wider than the line; dx2 ne 9baed400's cell.)
                            // (Nor after a comma with no space: Word keeps "१५००,क्रोटन" whole and parts before the digits; dx2 ne a6254f44's cell.)
                            // (Nor after a full stop with no space: Word keeps "म.न.पा./उप.म.न.पा/न.पा." whole and moves it to the next line, dx2 hi d91478e3.)
                            // (Nor after a Latin letter or digit with no space: Word keeps "…डीiseaseमल्टी…" whole, d912c25b; Devanagari only, Bengali ben-z17281487 drops with it.)
                            if let before = ctx.before, !"([{\u{2018}\u{201C}\u{FF08}".contains(before), before != "/", before != ",", before != ".", !(before.isASCII && (before.isLetter || before.isNumber) && u >= 0x905 && u <= 0x97F) {
                                spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                                ctx.inserts.append(offset)
                            }
                            spans.append(TextSpan(text: "\u{2060}", style: joiner))
                            ctx.inserts.append(offset)
                        }
                    }
                }
                // (Not where the face gives the quote a width of its own
                // (`otherAdvances`): Arial Unicode MS's are narrow, and Word
                // sets them so with no blank beside them — zh-0aac9d1a.)
                narrowFamily = run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                   ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily
                // (Asked once per family, not once per character.)
                if let known = _narrowQuoteMemo[narrowFamily ?? ""] {
                    narrowQuotes = known
                } else {
                    narrowQuotes = theme.faceResolver?(narrowFamily, true)?.otherAdvances?[0x201D] != nil
                    _narrowQuoteMemo[narrowFamily ?? ""] = narrowQuotes
                }
                quote = ea && fullQuotes && (ch == "\u{201C}" || ch == "\u{2018}" || ch == "\u{201D}" || ch == "\u{2019}")
                    && !narrowQuotes
                // (None where the face's own quote is the em to a hair: Starling
                // FangSong's is 15.99997 of 16, and a blank of that hair sent
                // the squeeze the line fitting asked of an opening quote into a
                // joiner that cannot be narrower than nothing — zh-8186c98d's
                // "…中的标准计" lost its "计" on Linux.)
                blank = quote ? max(0, em - _glyphWidth(style(kind), ch)) : 0
                blankShown = blank > _px(0.01) ? blank : 0
                led = false
                // (A word joiner before spaces that open the paragraph:
                // the engine moves a line on by half its first character's
                // letter spacing and, justifying, folds the spaces a line
                // opens with — zh-b378d8c4's "    1.城市内涝…", four Times
                // spaces widened to 7pt each, stand from the margin on
                // every line in Word's print, where ours started its
                // left-aligned lines 1.8pt in and set its justified ones'
                // spaces as one, 5pt out of the margin.)
                if theme.wordRules, offset == 0, ch == " " {
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    ctx.inserts.append(offset)
                }
                // (Thai, under `thaiBreaksAtSpaces`, kept together between
                // its spaces: Word for Mac's print of zh-6a4fc013 ends its
                // Thai lines only at spaces — "…ในประเทศต้นทาง" / "และพิจารณา…",
                // a justified line's gaps stretched for it — where the
                // engine's dictionary broke inside words and set 596 lines
                // to Word's 614.)
                // (A second space in a justified line, set as a patch of its
                // own: the engine takes a run of spaces for one gap and gives
                // the run one step, so "igreja.  Nos" lost a space; the
                // joiner between them makes each space a gap, stretched as
                // its neighbour is, as PowerPoint's print of Divino_Revelado
                // p12 sets them — 12.9pt for two where ours had 7.)
                else if !theme.wordRules, ch == " ", ctx.before == " ", p.style.alignment == .justify {
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    ctx.inserts.append(offset)
                }
                else if offset > 0, thaiJoins.contains(-offset), RichTextTheme.wordWindowsPages {
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    ctx.inserts.append(offset)
                }
                else if thaiJoins.contains(offset), let b = ctx.before,
                        let pb = b.unicodeScalars.first?.value, let pc = ch.unicodeScalars.first?.value,
                        (0x0E01 ... 0x0E5B).contains(pb), (0x0E01 ... 0x0E5B).contains(pc) || [0x201D, 0x2019, 0x22, 0x27, 0x29, 0x5D, 0x7D, 0xBB].contains(pc) {
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    ctx.inserts.append(offset)
                }
                else if let breaks = index.flatMap({ _hanChunks[$0] }), breaks.contains(offset) {
                    // (Word starts a long piece that does not fit the line's rest on a fresh line:
                    // `_hanPieceMoves`.)
                    flush(i)
                    spans.append(TextSpan(text: "\n", style: zeroWidth(current ?? kind)))
                    ctx.inserts.append(offset)
                }
                else if hanJoins.contains(offset) {
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    ctx.inserts.append(offset)
                }
                // (A place to break the line before a tab that follows text, where Word for Windows
                // takes the tab and what stands after it to the next line whole: tdf164499's
                // "…habe?)<tab>1" in a contents line — the number is no room, the dotted tab and
                // "1" go down and "habe?)" stays; the engine has no break there, wrapped "habe?)"
                // with them, and a line behind the contents ran on.)
                // (Not where a dotted right stop a little past the margin is honoured in a paragraph that is not
                // justified (`word-right-tab-past-the-margin-is-honoured`): the number ends on the same line.)
                else if theme.wordRules, RichTextTheme.wordWindowsPages, ch == "\t", offset > 0, let b = ctx.before,
                        b != " ", b != "\t", b != "\n", b != "\u{2028}", b.isASCII || (following == "\t" && RichLayout.isEastAsian(b, hinted: false)),
                        (p.style.alignment == .justify || !p.style.tabStops.contains(where: { s in
                            let edge = textWidth + _px(_listIndents(p, document)?.left ?? p.style.indentLeft)
                            return s.alignment == .right && !(s.leader ?? "none").isEmpty && s.leader != "none"
                                && _px(s.position) > edge + 0.5 && _px(s.position) <= edge + _px(RichLayout._tabPastMargin) + 0.5
                        })) {
                    // (An ideograph before a run of tabs as well (not a lone tab: zh-ab1ea005's contents lines): zh-77bd4900 p10's "…人數不得<tab><tab><tab>低於十人"
                    // keeps "得" on its line in Word's print and sends the tabs down; ours took "得" with them.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind)))
                    ctx.inserts.append(offset)
                    RuleTrace.hit("break-ctx.before-a-tab")
                }
                // A zero-width space where Word may break the line and
                // the engine would not: after spaces set as no-break
                // ones (`heldSpaces`), and before an opening curly
                // quote or after a closing one, as at any bracket —
                // the engine breaks on neither side of a quote.
                _sblk1()
                // (The opening quote's blank: a word joiner as wide as
                // the blank, which no line parts from the quote — at a
                // line's start the blank leads the mark, as in Word,
                // and none is left at the end of the line before. What
                // the line fitting takes off the quote comes off it.)
                if quote, blankShown > 0, ch == "\u{201C}" || ch == "\u{2018}" {
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: style(kind).copyWith(letterSpacing: max(0, blankShown + (adjust[offset] ?? 0)))))
                    ctx.inserts.append(offset)
                    led = true
                }
                ctx.beforeBefore = ctx.before
                if ch == "(" || ch == ")" || ch == "-" { ctx.latinRunBracket = true } else if !ch.isASCII || ch == " " { ctx.latinRunBracket = false }
                if ch.isASCII, ch != " " { ctx.latinAfterEastAsian = ctx.latinAfterEastAsian || (ctx.before.map { c in let v = c.unicodeScalars.first?.value ?? 0; return !c.isASCII && v >= 0x2E80 } ?? false) } else { ctx.latinAfterEastAsian = false }
                ctx.before = ch
                if ch == "\u{00A0}" { ctx.spacesAfterNbsp = true } else if ch != " " { ctx.spacesAfterNbsp = false }
                ctx.wordHasLetter = ch.isASCII && (ch.isLetter || ch.isNumber || ch == "-") ? ctx.wordHasLetter || ch.isLetter : false
                if let c = current, c != kind { flush(i) }
                else if joinedFace != nil, isArabic(ch) != (ctx.beforeBefore.map(isArabic) ?? false) { flush(i) }
                current = kind
                // What this character is set wider or narrower by: Word's
                // automatic space between an ideograph and the Latin
                // letter or digit beside it (`w:autoSpaceDE` and
                // `w:autoSpaceDN`, on unless the paragraph says
                // otherwise); the half em it takes off the first of two
                // punctuation marks that stand together; and what the
                // line fitting asked of this one.
                // (What the joiner could not give, the quote gives.)
                extra = led ? min(0, blankShown + (adjust[offset] ?? 0)) : adjust[offset] ?? 0
                if quote, !led { extra += blankShown }
                // (Balanced, a half-width character takes half of the
                // grid's addition, whatever follows it: on a grid of
                // 1.008pt Word sets a digit 0.504 wider than its face
                // does, before another and before an ideograph, and a
                // bracket and a letter the same. Lab `cg3`, 2026-10-13,
                // glyph by glyph. It was the full addition before an
                // ideograph here, which the automatic space hid — see
                // the gap below — and a paragraph with that space off
                // showed: zh-457a8d62 lost a character a line.)
                // (The paragraph's last character too: zh-72da925e's 12pt
                // cell "(內湖)" is 39.02 on its grid of 1.0076 — lab tgr,
                // windows-1: Word sets each character at whole multiples
                // of the pitch, half-width ones at half — and fits its
                // 39.05 column in Word for Windows' print; ours gave the
                // closing ")" the whole addition, 39.53, and wrapped it.)
                // (Word for Windows': the Mac's print of the same file
                // gives that last character the whole addition — its
                // pair fell 86.7 -> 71.1 with this — so there it stays.)
                if !ea, document.balancesSpaceWidth, let g = grid, g != 0, ch != " ",
                   following.map({ $0 != " " }) ?? (theme.wordRules && RichTextTheme.wordWindowsPages) {
                    extra -= _px(g) / 2
                } else if !ea, theme.wordRules, RichTextTheme.wordWindowsPages, document.balancesSpaceWidth, let g = grid, g != 0,
                          ch == " " || following == " ", kind >= 0, !ctx.wideSpaces.contains(offset),
                          { () -> Bool in
                              // (Latin on both sides of the space: a letter before it, the space, or a space before a letter.)
                              let gapAt = ch == " " ? i : after
                              guard gapAt > text.startIndex, gapAt < text.endIndex else { return false }
                              let before = shown(text[text.index(before: gapAt)])
                              let afterGap = text.index(after: gapAt)
                              guard afterGap < text.endIndex else { return false }
                              let nxt = shown(text[afterGap])
                              return before != " " && nxt != " " && !RichLayout.isEastAsian(before, hinted: hinted) && !RichLayout.isEastAsian(nxt, hinted: hinted)
                          }() {
                    // (A plain space between Latin words, and the letter before it, are
                    // half-width characters like the rest: half the addition each. zh-c2c92639's
                    // contents page: a word gap was 2.25 + 1.5 g, Word's 2.25 + 0.5 g.)
                    extra -= _px(g) / 2
                }
                // (In a paragraph off the grid, that half alone — no
                // whole addition to take it from: zh-8d6f702e's "24小时…
                // 150毫米" paragraph, `w:snapToGrid` 0 on a grid of -0.21,
                // sets each digit 7.90 in Word's print, Times's 8 less
                // half; ours 8.00, and the line took nothing Word's does.
                // Before a space, or a space, nothing: zh-268f8d15's
                // footer "- 1 -" is Times's own widths. Nor in a header or
                // footer, which keeps to no grid: zh-3c055c9b's page number.)
                if !ea, grid == nil, document.balancesSpaceWidth, let g = ideographGrid, g != 0, _grid(index, document).pitch != nil,
                   ch != " ", let following, following != " " {
                    extra += _px(g) / 2
                }
                // (A symbol set in an East Asian face that gives it a width
                // of its own takes that width, and half the grid's addition
                // as a half-width character does: YaHei's "…" is 0.8135 em,
                // and zh-457a8d62's "……" are 13.52pt apiece at 16pt on its
                // grid of 1.0076 in Word's print — 13.016 and 0.504 — where
                // the stand-in's em-wide glyph and the whole addition set
                // them 17.01, and its line "…奢侈放蕩……等，足以損失" lost
                // its "失".)
                if kind == -9 { extra += cambriaWidth * em - _glyphWidth(style(kind), ch) }
                // (A quotation mark in a run that says `w:hint` "default" over
                // an East Asian ASCII face and a Latin hAnsi one is the hAnsi
                // face's, at its width: zh-785e46f8's “ ” in 仿宋_GB2312 over
                // a Times hAnsi are 7.1pt at 16pt in Word's print, where the
                // stand-in set them 8.0 and the line lost a character.)
                if theme.wordRules, !ea, ch == "\u{201C}" || ch == "\u{201D}" || ch == "\u{2018}" || ch == "\u{2019}",
                   (run.fontHint ?? named?.char.fontHint) == "default", latinFace?.isEastAsian == true, highFace.map({ !$0.isEastAsian }) == true,
                   let high = run.hAnsiFontFamily ?? named?.char.hAnsiFontFamily {
                    var alt = run
                    alt.fontFamily = high
                    let s = theme.textStyle(for: alt, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                            eastAsian: false, gridPitch: pitch, characterClass: nil, characterGrid: grid, scriptHidden: true)
                    extra += _glyphWidth(s, ch) - _glyphWidth(style(kind), ch)
                }
                // (And a "×" or "÷" so set, at the hAnsi face's width: see `ea` above.)
                if !ea, latinDash, RichTextTheme.wordWindowsPages, ch == "\u{00D7}" || ch == "\u{00F7}",
                   let high = run.hAnsiFontFamily ?? named?.char.hAnsiFontFamily {
                    var alt = run
                    alt.fontFamily = high
                    let s = theme.textStyle(for: alt, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                            eastAsian: false, gridPitch: pitch, characterClass: nil, characterGrid: grid, scriptHidden: true)
                    extra += _glyphWidth(s, ch) - _glyphWidth(style(kind), ch)
                }
                // (A dash set in the hAnsi face's Times is half an em, as Word prints it: lab `semi` round 3 (Word for
                // Windows, zh-ea70c30e's 12.5pt PMingLiU run over a Times hAnsi): every "–" is 6.24, ours 5.88, and the
                // three of a line made it 1.1pt too short — it took "動" Word sends down.)
                if !ea, latinDash, RichTextTheme.wordWindowsPages, ch == "\u{2013}", highFace == nil || highFace.map({ !$0.isEastAsian }) == true {
                    extra += em / 2 - _glyphWidth(style(kind), ch)
                }
                // (An em space is an em and an en space half one, whatever face
                // sets them: zh-8415d258's paragraphs open with two U+2003 in
                // a 仿宋_GB2312 run, 15pt apiece at 15pt in Word for Windows'
                // print (in Cambria Math), where the stand-in's fallback set
                // them 6.7 and every such first line took a character more.)
                // (Arial has the en space itself, 0.557 em: ten of them are 66.84pt at
                // 12pt in Word's print — lab `spaces` — where the half em makes them 60.)
                // (A no-break space is not ASCII to Word: in a run whose ASCII
                // face is East Asian over a Calibri hAnsi it is Calibri's
                // space, 0.2261 em, not the East Asian face's half em —
                // zh-ea43dd6d's signature line, eight U+00A0 then 25 spaces
                // before "嘉兴市财政局" in 仿宋_GB2312 at 16pt: the eight
                // are 3.6pt each in Word's print, and ours set them 8 and
                // wrapped the name.)
                nbspHAnsi = theme.wordRules && RichTextTheme.wordWindowsPages && !ea && ch == "\u{00A0}" && latinFace?.isEastAsian == true
                    && !run.hAnsiNamedAsAscii && !(run.fontFamily == nil && (named?.char.hAnsiNamedAsAscii ?? false))
                    && hAnsiFace.map({ !$0.isEastAsian && ["calibri", "carlito"].contains($0.family.lowercased()) }) == true
                if nbspHAnsi {
                    RuleTrace.hit("no-break-space-is-the-hansi-faces-not-the-east-asian-ones")
                    extra += 0.2261 * em - _glyphWidth(style(kind), ch)
                }
                if theme.wordRules, ch == "\u{2003}" || ch == "\u{2002}" {
                    let arial = ch == "\u{2002}" && (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").lowercased() == "arial"
                    extra += (ch == "\u{2003}" ? 1 : arial ? 0.557 : 0.5) * em - _glyphWidth(style(kind), ch)
                }
                // (A symbol face's glyph drawn by a stand-in takes the face's
                // own advance: Wingdings 2's box is 0.89 em in Word's print
                // of zh-d0a207ac, 10.68 at 12pt, where the stand-in's is an
                // em, and its "☐鲁班杯" line lost its "杯".)
                if symbolsShown, let w = theme.symbolAdvance?(run.fontFamily ?? named?.char.fontFamily, ch) { extra += w * em - _glyphWidth(style(kind), ch) }
                // (The ballot box with check ☑, U+2611, in a SimSun run is Segoe
                // UI Symbol's in Word's print — 1758/2048 = 0.858 em — where the
                // fallback face here sets it 0.89 and zh-a7a889eb's
                // "☑10、…复印件" lost its last character.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, ch == "\u{2611}", !(symbolsShown && theme.symbolAdvance?(run.fontFamily ?? named?.char.fontFamily, ch) != nil) {
                    RuleTrace.hit("ballot-box-with-check-is-segoe-ui-symbols")
                    extra += (1758.0 / 2048.0) * em - _glyphWidth(style(kind), ch)
                }
                // (The long double arrow ⟺, U+27FA, is Cambria Math's in Word for Windows' print, 1.183 em
                // (14.2 pt at 12 pt, jpn-z21601833-4e6465 p12), where the fallback face here sets it 1.43.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, ch == "\u{27FA}" {
                    RuleTrace.hit("long-double-arrow-is-cambria-math")
                    extra += 1.1836 * em - _glyphWidth(style(kind), ch)
                }
                // (The rightwards arrow → in a Cambria run is 10.05 pt at 12 pt in Word for Windows' print
                // (jpn-z21601833-4e6465 p16: 301.3 to 311.3, 388.1 to 398.2), 0.8374 em, where the fallback sets it 0.8.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, ch == "\u{2192}",
                   (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily ?? "").lowercased() == "cambria" {
                    RuleTrace.hit("rightwards-arrow-in-cambria")
                    extra += (1715.0 / 2048.0) * em - _glyphWidth(style(kind), ch)
                }
                // (A Hangul syllable is an em wide in every Korean face
                // Word for Windows sets it in — Malgun Gothic, Gulim, Batang:
                // all 1.000 em across the kor batch B prints — where the
                // Noto Sans CJK stand-in's is 0.92. Lines held 8% more text
                // and the pages drifted.)
                // (A face that carries its Hangul em (U+AC00 of otherAdvances) has it set in Slides too: PowerPoint's Malgun Gothic, and
                // the Malgun it draws for a Korean face the machine lacks, step 1.000 em where the stand-in's is 0.92.)
                if (theme.wordRules && RichTextTheme.wordWindowsPages) || (!theme.wordRules && theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                       ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.otherAdvances?[0xAC00] != nil),
                   let u = ch.unicodeScalars.first?.value,
                   u >= 0xAC00 && u <= 0xD7A3 {
                    let g = _glyphWidth(style(kind), ch)
                    // (A face may carry its own Hangul em under U+AC00 of otherAdvances: NanumGothic 0.94.)
                    let hEm = (theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                                   ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true).flatMap { (style(kind).fontWeight == .bold ? $0.boldOtherAdvances?[0xAC00] : nil) ?? $0.otherAdvances?[0xAC00] }).map { $0 * em * wScale } ?? em * wScale
                    // (A character scale, w:w, narrows the syllable too: dx2 211f43df's 95% Gulim 11 pt is 10.44 in Word's print, 11.04 here.)
                    if g > 0.5, hEm < em * wScale ? abs(g - hEm) > 0.01 : g < hEm - 0.01 {
                        RuleTrace.hit("hangul-syllable-is-an-em")
                        extra += hEm - g
                    }
                    // (PowerPoint sets no pair kerning between Hangul syllables (ko-439a1778 p17: all 18 "가들" steps 18.0 pt); the stand-in's pairs are not Malgun Gothic's, so a syllable followed by one keeps its own width.)
                    if !theme.wordRules, let fv = following?.unicodeScalars.first?.value, fv >= 0xAC00 && fv <= 0xD7A3, following?.unicodeScalars.count == 1 {
                        let pair = _pairAdvance(style(kind), ch, following!)
                        if abs(pair - g) > 0.001 {
                            RuleTrace.hit("hangul-pair-is-not-kerned")
                            extra += g - pair
                        }
                    }
                    // (Where single and double byte widths are balanced, a spaced syllable in Malgun Gothic is set apart by the spacing ONCE
                    // (12 pt spaced -0.5 is 11.5 apart in xd 89a3482a's print); Gulim, Batang and HY Shinmyeongjo take it twice, as an ideograph does.)
                    if doubles, kind < 0, let fam = run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                                      ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily,
                       fam == "맑은 고딕" || fam.lowercased() == "malgun gothic" {
                        RuleTrace.hit("malgun-hangul-takes-spacing-once")
                        extra -= spacing
                    }
                }
                if ea || (ch == "\u{B7}" && (run.loneDot || tcFit) && theme.wordRules), let u = ch.unicodeScalars.first?.value, u < 0x2E80 || (u >= 0x3000 && u < 0x3100) || (u >= 0xFF00 && u < 0xFF60),
                   let eaFace = theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                                    ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true),
                   ea || eaFace.malgunSymbols,
                   var w = (style(kind).fontWeight == .bold ? eaFace.boldOtherAdvances : eaFace.otherAdvances)?[u] {
                    // (A run holding ONLY the middle dot has no Hangul to take Batang from, so Word draws it in Malgun
                    // Gothic: 0.2188 em (bold 0.2617), where a dot inside a Hangul run is Batang's 0.333. 28dd0ac0's title.)
                    if u == 0xB7, eaFace.malgunSymbols, theme.wordRules, RichTextTheme.wordWindowsPages, run.loneDot || tcFit {
                        RuleTrace.hit("lone-middle-dot-run-is-malgun")
                        w = style(kind).fontWeight == .bold ? 0.2617 : 0.2188
                        // (And once the run's spacing, not twice: 2.5 pt at 12 pt spaced -0.2 in 4fabe1f2's print, ours 2.2.)
                        if doubles, kind < 0 { extra -= spacing }
                    }
                    // (A white circle or triangle in a run that names no face of its own, inheriting a Korean face Word lacks, is
                    // Malgun Gothic's, an em: xd 4fabe1f2's eq \\o\\ac(○,예) rings step 11.7 pt at 12 pt in Word's print, ours 6.8 from
                    // the YaHei-like 0.604 em.)
                    if (u == 0x25CB || u == 0x25B3), w == 0.604, run.eastAsiaFontFamily == nil, !eaFace.malgunSymbols, theme.wordRules, RichTextTheme.wordWindowsPages, document.usesEastAsianLayout {
                        RuleTrace.hit("inherited-missing-korean-face-circle-is-an-em")
                        w = 1.0
                    }
                    extra += (w ?? 0) * em - _glyphWidth(style(kind), ch)
                    // (Likewise a white circle or triangle in an ascii-only run of a Korean face Word lacks: it is Malgun's, and "○○" at 12 pt
                    // spaced -0.2 steps 11.76 in c466d30a's print, ours 11.6.)
                    if doubles, kind == -4, run.eastAsiaFontFamily == nil, RichTextTheme.wordWindowsPages, document.usesEastAsianLayout,
                       u >= 0x25A0, u <= 0x25EF, eaFace.malgunSymbols, run.fontFamily != nil {
                        RuleTrace.hit("malgun-shape-takes-spacing-once")
                        extra -= spacing
                    }
                    if document.balancesSpaceWidth, let g = grid, g != 0 { extra -= _px(g) / 2 }
                }
                // (Fit text: Word gives the middle dot only HALF a gap after it, labs dot1 and mar2: 7.2 pt after a Malgun dot
                // at 24 pt where a full gap is 11.7; the gap before it is the full one, from the letter ahead.)
                if ch == "\u{B7}", tcFit, fitGroup != nil, let f = fitSpacing() { extra -= f / 2 }
                // (A CJK compatibility ideograph YaHei lacks and Word for
                // Mac's Noto Sans SC does not give it is YaHei's own
                // missing-glyph box, 0.697 em, in the line's breaking as
                // in its drawing: zh-12c4f07a's "於契約…本委" ends at "委"
                // in Word's print, its "契" U+F909 a box 9.06pt wide at
                // 13pt, where ours set it an em and "委" went over. Lab
                // `cj` (Word for Mac): U+F909 and U+FA01 give 0.30 em more
                // room than U+5951 and U+5EA6, at 13 and 14pt, anywhere on
                // the line.)
                if ea, let u = ch.unicodeScalars.first?.value, u >= 0xF900, u <= 0xFAFF, !RichLayout._notoCompatibility.contains(u),
                   theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                       ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.lacksCompatibilityIdeographs == true {
                    extra += 0.697 * em - _glyphWidth(style(kind), ch)
                }
                // A symbol an East Asian run sets in its own face (■□●○
                // ◆△※, the circled numbers, arrows) is an em wide there, as
                // every such face draws it; the face drawing it here may
                // be a Latin fallback's narrower glyph — zh-abe7e063's ■
                // came out 6.04pt at 10pt where Word's SimSun sets 10, and
                // a table cell's line took a character Word wraps.
                // (So is the hyphenation point "‧", U+2027 — the zh-TW
                // middle dot of "亞洲‧矽谷" — and the bullet and two-dot
                // leader beside it, whichever kind the layout counts
                // them: PMingLiU sets each an em, and zh-190d730c's
                // line of it at 6.2pt took a character Word wraps.)
                // (A circled digit 1-10 in a run whose face is a Korean one Word lacks and prints in Batang (a Malgun-symbols face) is
                // Malgun Gothic's, an em: 11.8 pt at 12 pt spaced -0.2 in xd 107500a8's print, ours 11.6.)
                malgunDigit = {
                    guard theme.wordRules, RichTextTheme.wordWindowsPages, ch.unicodeScalars.count == 1,
                          let d = ch.unicodeScalars.first?.value, d >= 0x2460, d <= 0x2469 else { return false }
                    return theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                               ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.malgunSymbols == true
                }()
                if malgunDigit { RuleTrace.hit("malgun-circled-digit-em") }
                // (The JIS symbols in Latin-1 (§ ¨ ° ± ´ ¶ × ÷) are an em in MS Mincho, MS Gothic and GulimChe, the fixed half-em Latin
                // faces, where ASCII is half an em: Word's own metrics, and 5dc87fc7's "°" at 12 pt took 12 pt where our Liberation
                // stand-in's 4.8 let it stay on a line Word wraps. Where the face drawing the character is that face: the hAnsi slot's,
                // under no w:hint, which already makes it East Asian and an em.)
                jisLatin1 = _jisLatin1Symbol(ch, theme: theme, run: run, named: named, document: document, hint: hint)
                if jisLatin1 {
                    RuleTrace.hit("jis-latin1-symbol-em")
                    let g = _glyphWidth(style(kind), ch)
                    // (Word's MS Mincho table: · and ˇ are half an em, the rest an em.)
                    // (¡ and ¿ too: half an em in the print, 6.0 pt at 12 pt, 5dc87fc7 E31, where the stand-in's 4.0 and 7.3 are not.)
                    let half = ch == "\u{B7}" || ch == "\u{2C7}" || ch == "\u{A1}" || ch == "\u{BF}"
                    let target = half ? em * 0.5 : em
                    if g < target - 0.01 || (half && g > target + 0.01) { extra += target - g }
                }
                if let u = ch.unicodeScalars.first?.value,
                   !(symbolsShown && theme.symbolAdvance?(run.fontFamily ?? named?.char.fontFamily, ch) != nil),
                   !(theme.wordRules && RichTextTheme.wordWindowsPages && u == 0x2611),
                   (ea && u >= 0x2190 && u <= 0x266F) || malgunDigit || u == 0x2027 || u == 0x2025 || (ea && u == 0x2022)
                    // (And the reference mark ※ where the run's Latin face is a square face too: zh-ae2dd08d's
                    // 標楷體 "※依照財政部…" sets it 14pt at 14 in Word's print, where DejaVu's 11.8 took "就"
                    // onto the line.)
                    || (u == 0x203B && (ea || latinFace?.isEastAsian == true)),
                   theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                       ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.fullWidthSymbols == true || malgunDigit {
                    let g = _glyphWidth(style(kind), ch)
                    if g > 0.5, g < em - 0.01 { extra += em - g }
                    // (Word takes the run's spacing ONCE on a Malgun circled digit, not twice as on a Hangul syllable: 11.8 pt at 12 pt
                    // spaced -0.2, xd 4fabe1f2's "②".)
                    if malgunDigit, doubles, kind < 0 { extra -= spacing }
                }
                _sblk2()
                if theme.wordRules, RichTextTheme.wordWindowsPages, kind == -1, let following, ch.unicodeScalars.count == 1, following.unicodeScalars.count == 1,
                   let u = ch.unicodeScalars.first?.value, let v = following.unicodeScalars.first?.value, u >= 0x3040, u < 0x3100, v >= 0x3000, v < 0x3100,
                   let pair = RichLayout.yuMinchoKerns[u << 16 | v],
                   (style(kind).debugLabel?.lowercased()).map({ $0.containsSubstring("yu mincho") || $0.containsSubstring("游明朝") }) == true,
                   let from = run.kerningFrom ?? named?.char.kerningFrom ?? _normalChar(document)?.kerningFrom, from > 0,
                   (run.fontSize ?? named?.char.fontSize ?? theme.fontSize) >= from {
                    extra += pair * em
                    // (A pair across a line's end is no kern in Word: its fit counts the last character at its own
                    // advance. xb jpn 1e9281, ec6c96: "…名称として" with the "し" kerned 0.52 into 0.05 pt of room ends
                    // the line at "と" in Word's print.)
                    if let ix = index { _yuEndKern[ix, default: [:]][offset] = pair * em }
                }
                if yuOfMissingHangul, kind >= 0, let u0 = ch.unicodeScalars.first?.value, ch.unicodeScalars.count == 1, u0 >= 0x20, u0 < 0x7F {
                    // (Word's Yu Gothic Latin in a paragraph whose Hangul-named face it lacks: 22de7d.)
                    let s = style(kind)
                    let bold = s.fontWeight == .bold
                    // (Word's print of 22de7d: a space between Latin neighbours is Yu Gothic's 0.2852 em, 2.87 pt at 10 pt; one beside a Hangul syllable stays 0.5 em, 5.04 pt.)
                    // (A leading space, or one beside another space, keeps 0.5 em too: Word's 3-space indent after a line break is 15.1 pt.)
                    let hangulBeside = ![i > text.startIndex ? Optional(text[text.index(before: i)]) : nil, following].allSatisfy { c in
                        guard let v = c?.unicodeScalars.first?.value else { return false }
                        return v > 0x20 && !((v >= 0xAC00 && v <= 0xD7A3) || (v >= 0x1100 && v <= 0x11FF) || (v >= 0x3130 && v <= 0x318F))
                    }
                    let a: Double? = u0 == 0x20 ? (aumsLatin || !hangulBeside ? 584.0 / 2048 : 0.5) : (u0 == 0x28 ? Optional(791.0 / 2048) : (bold ? RichLayout.yuGothicBold : RichLayout.yuGothicRegular)[u0].map { Double($0) / 2048 })
                    // (The size-compensated stand-in grows lowercase letters' style size; the advance is the nominal size's, the capitals' kind.)
                    if let a, let px = style(classed ? RichResolvedFace.characterClass("H") : 0).fontSize, px > 0.5 {
                        RuleTrace.hit("word-missing-hangul-face-latin-takes-yu-gothic-advances")
                        extra = a * px - _glyphWidth(s, ch) + (adjust[offset] ?? 0)
                    }
                }
                _sblk3()
                _sblk4()
                if let joiner = compatJoinerAfter {
                    compatJoinerAfter = nil
                    flush(after)
                    spans.append(TextSpan(text: "\u{2060}", style: joiner))
                    ctx.inserts.append(offset + ch.utf16.count)
                }
                offset += ch.utf16.count
                i = after
            }
            flush(text.endIndex)
            if spaceBeforeDanda, let k = current ?? Optional(0) { spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(k))); ctx.inserts.append(base + text.utf16.count) }
            return spans
    }
}
