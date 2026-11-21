// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Span+Styled": the `styled` step of `_span` (once a closure inside it; a pure move: the variables it
// shares with `_span` are `_SpanCtx`, passed inout).

import Flutter
import FlutterSwiftBridge
import Foundation

extension RichLayout {
    func _spanStyled(_ ctx: inout _SpanCtx, _ rawText: Substring, _ run: CharStyle, at base: Int = 0, next: Character? = nil, symbolsShown: Bool = false) -> [TextSpan] {
        let p = ctx.p
        let index = ctx.index
        let document = ctx.document
        let textWidth = ctx.textWidth
        let lead = ctx.lead
        let adjust = ctx.adjust
        let held = ctx.held
        let fitProbe = ctx.fitProbe
        let autoSpaces = ctx.autoSpaces
        let capped = ctx.capped
        let eaFaceOffset = ctx.eaFaceOffset
        func eastAsianFaceIsLatin(atOffset o: Int) -> Bool { ctx.eastAsianFaceIsLatin(o) }
        func runHinted(atOffset o: Int) -> Bool { ctx.runHinted(o) }
        let breaksAtQuotes = ctx.breaksAtQuotes
        let fullQuotes = ctx.fullQuotes
        let hanJoins = ctx.hanJoins
        let heldSpaces = ctx.heldSpaces
        let kinsokuOff = ctx.kinsokuOff
        let koreanSpaces = ctx.koreanSpaces
        let koreanTokenJoins = ctx.koreanTokenJoins
        let lineSize = ctx.lineSize
        let mixedRubyRaise = ctx.mixedRubyRaise
        let named = ctx.named
        let openerBeforeLatin = ctx.openerBeforeLatin
        let pausesOpenLines = ctx.pausesOpenLines
        let percentStarts = ctx.percentStarts
        let pitch = ctx.pitch
        let plainNoLineRules = ctx.plainNoLineRules
        let raised = ctx.raised
        let thaiJoins = ctx.thaiJoins
        let thaiParagraph = ctx.thaiParagraph
        let traditionalLists = ctx.traditionalLists
        let vertical = ctx.vertical
        let wholeRaised = ctx.wholeRaised
        let wideIndicWords = ctx.wideIndicWords
        let windowsCounted = ctx.windowsCounted
        let mixedLatinFaces = ctx.mixedLatinFaces
        let trailingSpaces = ctx.trailingSpaces
        var paragraphLatinOwner: String? { ctx.paragraphLatinOwnerFn() }
            // (U+FE0F after a text-style emoji draws it in colour, U+FE0E after a colour one as an outline: each such
            // pair is a piece of its own, in its own face.)
            if !ctx.splittingVariation, let pieces = Self._variationPieces(rawText) {
                ctx.splittingVariation = true
                defer { ctx.splittingVariation = false }
                var out: [TextSpan] = []
                var at = base
                for (k, piece) in pieces.enumerated() {
                    let after = k + 1 < pieces.count ? pieces[k + 1].text.first : next
                    let spans = _spanStyled(&ctx, Substring(piece.text), run, at: at, next: after, symbolsShown: symbolsShown)
                    out += piece.kind == 0 ? spans : spans.map {
                        TextSpan(text: $0.text, children: $0.children, style: Self._variationStyle($0.style, kind: piece.kind), recognizer: $0.recognizer, locale: $0.locale)
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
               Self._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") != nil,
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
            var run = run
            var hyphenFace: String? = nil
            // (Georgian letters in a run whose face has none: Word's print draws them in Sylfaen, at its 1.317 em line and its widths, where the stand-in
            // drew DejaVu Sans's. dx2 72f67d49, Calibri runs under the theme's Geor = Sylfaen: Word 52 lines at 15.7 pt, ours 55 at 14.5.)
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
            let bidiLanguage = [run.keptXML, named?.char.keptXML].compactMap({ Self._attribute($0, "w:bidi") }).first ?? Self._attribute(document.defaultLangXML, "w:bidi") ?? ""
            let wasRightToLeft = run.rightToLeft && !bidiLanguage.hasPrefix("fa")
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
            let moved: String? = {
                guard theme.wordRules, RichTextTheme.wordWindowsPages, run.rightToLeft, !p.style.rightToLeft,
                      let last = rawText.last, ":;.,!?".contains(last), rawText.count > 2,
                      !rawText.dropLast().contains(where: { ch in ch.unicodeScalars.contains { ArabicForms.isArabic($0.value) || (0x590...0x8FF).contains($0.value) } || ":;.,!?".contains(ch) })
                else { return nil }
                return String(last) + rawText.dropLast()
            }()
            // (A closing run of ideographic spaces Word lets hang is set with no width: _cutTrailingSpaces.)
            let hung: String? = {
                guard let idx = index, let cut = _trailCut[idx], base + rawText.utf16.count > cut, rawText.containsSubstring("\u{3000}") else { return nil }
                var at = base, out = ""
                for c in (moved ?? String(rawText)) { out.append(c == "\u{3000}" && at >= cut ? "\u{200B}" : c); at += c.utf16.count }
                return out
            }()
            // (A space right before a danda does not hang in Word: the danda may not start a line, so the space is counted in the fit
            // and the line parts after it; lab dnd2, 33 right indents: "जाएगी " stays on a line only while the word and its space fit, the
            // danda alone below. The engine hangs a trailing space, so it is set as a no-break space with a break after it.)
            let spaceBeforeDanda: Bool = theme.wordRules && RichTextTheme.wordWindowsPages && rawText.last == " " && (next == "\u{0964}" || next == "\u{0965}")
                && p.text.unicodeScalars.contains(where: { $0.value >= 0x900 && $0.value <= 0x97F })
            let text0: Substring = (spaceBeforeDanda ? Substring(String((hung ?? moved ?? String(rawText)).dropLast()) + "\u{00A0}") : hung.map { Substring($0) } ?? moved.map { Substring($0) } ?? rawText)
            // (A space + U+00A0 gap after an Indic letter is not a place to part the line: Word moves the word before it down with
            // the gap and the word after, one unit. Lab nbsp4 (dx2 6dcc4527 p2): "ਵਿਚ" + SP + NBSP + "ਭਾਰਤ" returns to the line only when
            // the edge holds the whole unit (+31 pt), never when just "ਵਿਚ" + SP would fit; NBSP alone parts at +28, SP+NBSP+NBSP at
            // +34, plain spaces never block. The space is set as a no-break space (same width). Cyrillic, Georgian and Armenian gaps
            // (3200cbc7, a6d5c830, c423753e) do part, so only an Indic letter before the gap counts.)
            let text: Substring = {
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
            let latinFace = theme.wordRules || theme.setsFaceAdvances
                ? theme.faceResolver?(run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false) : nil
            // (The face Word sets the Latin characters past ASCII in, where
            // the run names one other than its ASCII face: `w:hAnsi`.)
            let highFace = latinFace == nil ? nil : (run.hAnsiFontFamily ?? named?.char.hAnsiFontFamily).flatMap { theme.faceResolver?($0, false) }
            // (Not where the run says `w:hint="default"` over a Latin hAnsi
            // face: its shared marks are that face's then —
            // zh-785e46f8's "产业链“链长" in 仿宋_GB2312 over a Times hAnsi
            // has its "“" in Times in Word's print, 7.1pt, where ours set
            // a full-width one, 16, and the line lost a character.)
            // (zh-7fd860f9's runs say the same hint over a 仿宋_GB2312
            // hAnsi, and their "“" is full-width in Word's print: the
            // hAnsi face decides.)
            let hint = run.fontHint ?? named?.char.fontHint
            // (A hint over an East Asian face that is itself a Latin one changes nothing: hin-z21320572's "ç", hinted over
            // Normal's Times New Roman, is drawn in the run's own face in Word's print, its line not the Times line's height.)
            let eaFaceIsLatin = theme.wordRules && hint == "eastAsia"
                && (run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily)
                    .flatMap { name in name.unicodeScalars.contains(where: { $0.value >= 0x2E80 }) ? nil
                        : theme.faceResolver?(name, false) }.map { !$0.isEastAsian } == true
            // (A right-to-left run's hinted dash stays its Latin face where the East Asian face is unnamed: heb-z5059159's
            // hinted "–" in Arial in Word's print, where the hint set the left-to-right "·" of fas-z22973278 in MS Mincho.)
            let eaNamedNone = run.rightToLeft && theme.wordRules && text.unicodeScalars.allSatisfy({ $0.value == 0x2013 || $0.value == 0x2014 }) && (run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily) == nil
            // (A hint where no East Asian face is named anywhere, over accented Latin letters only: sa2 1f26d09a's "çã"
            // stay the run's own Times in Word's print, its 1.5 lines 20.7 pt, where ours took a fallback face's height, 22.2.)
            let eaUnnamedLetters = theme.wordRules && hint == "eastAsia" && !text.isEmpty
                && text.unicodeScalars.contains(where: { $0.value >= 0xC0 && $0.value <= 0x24F })
                && text.unicodeScalars.allSatisfy({ ($0.value >= 0xC0 && $0.value <= 0x24F && $0.value != 0xD7 && $0.value != 0xF7) || $0.value < 0x80 })
                && (run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily) == nil
            let hinted = (hint == "eastAsia" && !eaFaceIsLatin && !eaNamedNone && !eaUnnamedLetters) || (latinFace?.isEastAsian ?? false) && (hint != "default" || (highFace?.isEastAsian ?? true))
            // (… but an en dash, unhinted, is its hAnsi face's where that is
            // a Latin one: zh-ea70c30e's "辦公室 – 投訴", `w:ascii` PMingLiU
            // over an inherited Times hAnsi, sets its "–" in Times in Word's
            // print, half an em, where ours drew PMingLiU's at 0.82. Its
            // quotes and other marks stay East Asian: taken as Latin too,
            // eight documents fell.)
            let hAnsiFace = highFace ?? (run.fontFamily == nil ? nil
                : (named?.char.hAnsiFontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily).flatMap { theme.faceResolver?($0, false) })
            let latinDash = theme.wordRules && (run.fontHint ?? named?.char.fontHint) != "eastAsia" && (latinFace?.isEastAsian ?? false)
                && hAnsiFace.map { !$0.isEastAsian } == true
            // (An em dash, unhinted, is its hAnsi face's where that is an East
            // Asian one over a Latin ascii face: ff493b's "—" in Aptos Bold
            // over a Malgun Gothic hAnsi is Malgun Bold in Word's print, and
            // makes its line 1.73 em tall; ours set it in Aptos.)
            let eastDash = theme.wordRules && RichTextTheme.wordWindowsPages && hint == nil
                && (latinFace?.isEastAsian != true || (run.hAnsiFontFamily != nil && run.hAnsiFontFamily != (run.fontFamily ?? named?.char.fontFamily)))
                && (run.hAnsiFontFamily ?? named?.char.hAnsiFontFamily).flatMap { theme.faceResolver?($0, false) }?.isEastAsian == true
            let em = (run.fontSize ?? named?.char.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
            // (The run's character scale, Word's `w:w`.)
            let wScale = RichTextTheme.wordWidthScale(run.horizontalScale ?? named?.char.horizontalScale ?? 1, wordRules: theme.wordRules,
                eastAsiaFamily: run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily)
            let closes = _closesUpMarks(run, named, document)
            // (So may text whose East Asian language has no such rules —
            // its run's own, else the document's: `eastAsianLineRules`.)
            let lineRulesOff = kinsokuOff || (theme.wordRules && !Self._eastAsianLineRules(run, document, named: named))
            // A stretch is of one script, and — where the Latin face
            // stands in at a scale for each kind of character — of one
            // kind: -1 East Asian, else the kind (0 where there is one
            // scale for all).
            let classed = latinFace?.classScales != nil
            // (A right-to-left run whose Latin face is Arial Narrow: its spaces, digits and marks are the Arabic text's, in Arial, not at the
            // narrow face's widths: the Urdu forms 8963bef7, f98daa05 and 0de57755.)
            let narrowLatinInRTL = theme.wordRules && run.rightToLeft && (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily)?.trimmingWhitespace().lowercased() == "arial narrow"
            var styles: [Int: TextStyle] = [:]
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
            let ownGridSay = run.keptXML?.containsSubstring("<w:snapToGrid") ?? false
            let runOffGrid = ownGridSay ? (run.keptXML?.containsSubstring("<w:snapToGrid w:val=\"0\"") ?? false)
                : theme.wordRules && (named?.char.keptXML?.containsSubstring("<w:snapToGrid w:val=\"0\"") ?? false)
            // (Latin text too, in a paragraph that takes itself off the
            // grid — not one its style takes off, as zh-268f8d15's footer's
            // and zh-3c055c9b's styles do: zh-c2f6d17a's paragraphs set
            // `w:snapToGrid` 0 on a grid of -0.207pt, and Word's print has
            // their Times digits 7.9 apart, half the grid's addition off
            // 8.0, as on it — ours set them 8.0, and a line of "120" and
            // "48" left a character Word takes.)
            // (On a snapToChars grid the cell is whole: an ideograph takes it, not its own size plus the addition; Latin text keeps its own width.)
            let cellFix = _gridCellBase(index, document).map { $0 - em / (theme.pixelsPerPoint * scale) } ?? 0
            let grid = theme.wordRules && !runOffGrid && (p.style.eastAsian["w:snapToGrid"] != "0" || p.style.ownGridOff)
                ? _grid(index, document).chars : nil
            // (On a snapToChars grid Latin glyphs keep their plain widths, and a stretch of them stands a whole number of cells: lab gr16a,
            // Word for Windows, "the survey of the coast was" 118.9 pt plain stands 11.0 cells of 11.08, "lighthouse" 47.0 stands 5.)
            let latinCell: Double? = theme.wordRules && grid != nil ? _gridCellBase(index, document).map { $0 * theme.pixelsPerPoint * scale } : nil
            let latinGrid = latinCell != nil ? 0 : grid
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
            let ideographGrid = (grid ?? (theme.wordRules && !runOffGrid ? _grid(index, document).chars : nil)).map { $0 + cellFix }
            // (Where single and double byte widths are balanced, a
            // full-width character takes the run's spacing twice: 16pt
            // text spaced -0.3 is set 15.4 apart.)
            let spacing = (run.letterSpacing ?? (theme.wordRules ? named?.char.letterSpacing ?? _normalChar(document)?.letterSpacing : nil) ?? 0)
                * theme.pixelsPerPoint * scale
            let doubles = theme.wordRules && document.balancesSpaceWidth && spacing != 0
            // A character an embedded subset lacks (`RichResolvedFace.covers`)
            // is set in the face the name has unembedded, Word's fallback,
            // its line that face's height (kind -3).
            let subsetFace = theme.wordRules
                ? theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                      ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true) : nil
            let uncovered = subsetFace.flatMap { face in face.uncoveredFamily.flatMap { alt in face.covers.map { (alt, $0) } } }
            // (Where Word takes them from several faces, each its own kind,
            // -10 down: `RichResolvedFace.uncoveredChain`.)
            let chain = uncovered != nil ? subsetFace?.uncoveredChain : nil
            var chainAt: Int? = nil
            var cambriaWidth = 0.0
            // (Whether the run's shapes are its Latin face's — no East
            // Asian hint, a Latin face that is not an East Asian one.)
            let latinShapes = theme.wordRules && run.fontHint != "eastAsia"
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
            let tcFit = theme.wordRules && RichTextTheme.wordWindowsPages && textWidth > 1
                && Self._tcFitParagraph(p, index, document)
            let fitGroup = theme.wordRules && RichTextTheme.wordWindowsPages
                ? (Self._fitText(run.keptXML) ?? (tcFit ? (textWidth / (theme.pixelsPerPoint * scale), "tc") : nil)) : nil
            var fitPitch: Double? = nil
            var fitBusy = false
            var plainPiece = false
            var latinNoScale = false
            // (A run names its Latin face itself, or takes one from its styles that is a Windows Latin face: xd 77d6ca49's ", AIESC" in
            // Calibri (Normal style), 12.0 in Word, 12.48 with the Indic scale.)
            let latinFaceNamed: Bool = {
                if run.fontFamily != nil { return true }
                guard theme.wordRules, RichTextTheme.wordWindowsPages else { return false }
                // (Devanagari and Gurmukhi paragraphs only: dx2 d611e23b, Telugu with Arial from Normal, draws its Latin at the Indic scale in Word; Gurmukhi: dx2 6af76fa9, Arial from the table style, "(ATAR)" is Arial's own width.)
                guard p.text.unicodeScalars.contains(where: { ($0.value >= 0x905 && $0.value <= 0x939) || ($0.value >= 0xA05 && $0.value <= 0xA39) }) else { return false }
                let f = (named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
                return !f.isEmpty && !f.hasPrefix("nirmala ui") && WordWindowsFaces.names.contains(f)
            }()
            var fitNone = false
            var fitLastSingle = false
            var fitLastEnd = 0
            // (What the painting below sets a character of a fit-text group wider than the stand-in's glyph, so the group's
            // spread is worked out from the widths Word's faces give: Hangul an em, the full-width symbols an em, and the
            // original face's own advance for the ASCII and the punctuation. dx2/xd 89a3482a's 12 pt w:w 87 group is 372 pt
            // and Word's step is 10.44 a letter, spread 0; measuring the stand-in's 9.6 gave 0.7 and the line wrapped.)
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
                    guard tcFit ? at + r.length <= units.count : (Self._fitText(r.style.keptXML)?.id == g.id && at + r.length <= units.count) else { continue }
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
                    let slack = Self._tcFitMarginSlack(p, document) * theme.pixelsPerPoint * scale
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
            // (Devanagari and Bengali, in Word for Windows: the face Word draws a run in, which sets its line (the joiner below) and its
            // width, as the face's own letters are wider or narrower than the Noto stand-in's — the ratio of the advances in the fonts Word's
            // prints embed, weighted by the letters the pages use: Mangal 1.096, Nirmala UI 1.086 (Bold 1.076, Bengali 1.062), Kokila 0.73.
            // A run mostly of such letters takes it whole. Which face: the complex-script one (Mangal, Kokila), but Kalpurush, which Windows
            // lacks, Word draws in Nirmala UI (ben-z17281487). hin-z18479909's Kokila runs print in Nirmala UI too, where mar-z19707447's and
            // hin-z20740649's, the same markup, print in Kokila: not explained (a print machine without Kokila regular?), the majority taken.)
            // (Kokila as the run's Latin face too: only then are its Latin, digits and space, and its line, Kokila's; with another Latin face
            // (cbb7ae39: Times New Roman beside a Kokila complex face) the Latin keeps that face.)
            let kokilaLatin = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "kokila"
            // (The same face seen from a run of Latin: dots, digits, or spaces alone on a line, lab siyam2; spaces after Bengali on its line add nothing.)
            let malgunLatin: Bool = theme.wordRules && RichTextTheme.wordWindowsPages && document.readFromFile
                && _malgunAlternate(run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily, document)
            // (Arial Unicode MS with the Japanese charset in the font table, no Indic letter in the paragraph: Word prints the Latin text in Yu Gothic, a 1.67 em
            // line; dx2 3922c734, a Danish form, lines 16.7 pt apart at 10 pt against ours 13.4.)
            let aumsLatin: Bool = theme.wordRules && RichTextTheme.wordWindowsPages && document.readFromFile && document.fontCharsets["arial unicode ms"] == "80"
                && (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms"
                && !p.text.unicodeScalars.contains(where: { Self._isIndic($0.value) || Self._tamil.contains($0.value) || $0.value >= 0x2E80 })
                && !(run.keptXML.map { $0.containsSubstring("<w:cs/>") || $0.containsSubstring("<w:cs ") } ?? false)
            // (Arial Unicode MS in an Indic paragraph, a run with no w:cs: its Latin, digits and marks take the ascii slot, which Word lacks and draws
            // in Yu Gothic, whose line every such run sets whatever it holds; lab aumsy2 (2026-11-09): at 9 pt the steps are 12.8 into and 14.2 out of
            // a Nirmala line, for GST, commas, brackets, dots, digits, "**", regular and bold. fb94294e.)
            // (A Hangul-named face Word's box lacks: its Latin letters, digits and spaces are Yu Gothic's, so they take Yu Gothic's advances; 22de7d.)
            let yuOfMissingHangul: Bool = aumsLatin || (theme.wordRules && RichTextTheme.wordWindowsPages && _yuLatinOfMissingHangulFace(run, named, document)
                && !document.hasIndicText)
            let aumsYuInIndic: Bool = theme.wordRules && RichTextTheme.wordWindowsPages && document.readFromFile && document.fontCharsets["arial unicode ms"] == "80"
                && (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms"
                && !(run.keptXML?.containsSubstring("<w:cs/>") ?? false) && !(run.keptXML?.containsSubstring("<w:cs ") ?? false)
                && p.text.unicodeScalars.contains(where: { $0.value >= 0x900 && $0.value < 0xB00 })
            let aumsSpaces: Bool = theme.wordRules && RichTextTheme.wordWindowsPages && document.readFromFile
                && (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms"
                && p.text.unicodeScalars.contains(where: { $0.value >= 0x900 && $0.value < 0xB00 })
            let mangalLatinSpace: Bool = theme.wordRules && RichTextTheme.wordWindowsPages && document.readFromFile
                && (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "mangal"
                && p.text.unicodeScalars.contains(where: { ($0.value >= 0x905 && $0.value <= 0x939) || ($0.value >= 0xA05 && $0.value <= 0xA39) })
            let utsaahLatin = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "utsaah"
            let namedFace: String? = text.unicodeScalars.contains(where: { $0.properties.isAlphabetic && Self._isIndic($0.value) }) ? nil : _namedMetricFace(run, named, document, text)
            // (Kalimati is a face Windows lacks, drawn in Mangal: a space-only paragraph whose MARK is a complex-script one (`w:cs`) takes Mangal's line,
            // as the stand-in cannot; dx2 9baed400's cell paragraph, 31.3 pt in Word's print where ours stood 25.8. A mark with no `w:cs` keeps the
            // Calibri line however the run is flagged: 72d5ef87's two space-only paragraphs, 56.7 pt.)
            var namedKalimati = false
            if namedFace == "mangal", !p.text.isEmpty, p.text.unicodeScalars.allSatisfy({ $0.value == 0x20 || $0.value == 0x09 || $0.value == 0x2E || ($0.value >= 0x30 && $0.value <= 0x39) }),
               let kept = p.style.mark?.keptXML, kept.containsSubstring("<w:cs/>") || kept.containsSubstring("<w:cs ") {
                let csK: String = run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? ""
                let asciiK: String = run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? ""
                let csFlagK: Bool = run.keptXML.map { $0.containsSubstring("<w:cs/>") || $0.containsSubstring("<w:cs ") } ?? false
                namedKalimati = (csFlagK ? csK : asciiK).trimmingWhitespace().lowercased() == "kalimati"
            }
            let indic: (face: String, scale: Double)? = {
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
                    // (Tamil: the line of Nirmala UI, 1.079 + 0.251 em, in the prints of tam-* and four of the xd Tamil documents.)
                    // (Width: set per word in flush() from TamilAdvances, a per-codepoint regression fit of Word's word widths
                    // (2864 words, four documents); our PDF embeds no Tamil face, so it cannot be read from glyph hmtx. No scale here.)
                    if text.unicodeScalars.contains(where: { Self._tamil.contains($0.value) }) {
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
                       !text.unicodeScalars.contains(where: { ($0.value < 0x980 && $0.value >= 0x900 && $0.value != 0x964 && $0.value != 0x965) || $0.value >= 0xA00 && Self._isIndic($0.value) }),
                       !["mangal", "kokila", "aparajita", "raavi", "shruti", "gautami", "vrinda", "utsaah", "shonar bangla", "kalimati", "latha", "vijaya"].contains(
                        (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()),
                       Self._bengaliMissingFace((run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased(), document) != "shonar bangla" {
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
                       Self._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") != nil,
                       p.text.unicodeScalars.contains(where: { $0.properties.isAlphabetic && $0.value >= 0x980 && $0.value <= 0x9FF }) {
                        RuleTrace.hit("word-danda-only-run-in-a-missing-bengali-face-is-mangal")
                        return ("mangal", 1)
                    }
                    // (A run of spaces and tabs in a missing Bengali face (Nikosh, SolaimanLipi) inside a paragraph of Bengali letters: Word draws the spaces in Mangal
                    // but they do not raise the line, which stays Nirmala UI's 1.33 em: dx2 2263e221's bold heading, 14.6 pt apart in Word, 18.5 in ours.)
                    if !text.isEmpty, !text.unicodeScalars.contains(where: { $0.value != 0x20 && $0.value != 0x09 }),
                       Self._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") != nil
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
                        || !p.text.unicodeScalars.contains(where: { Self._isIndic($0.value) }) && text.unicodeScalars.contains(where: { $0.value == 0x20 }) {
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
                default: face = top.key == "B" ? Self._bengaliMissingFace(cs, document) : (document.devanagariFirstRunMangal && cs != "times new roman" ? "mangal" : "nirmala ui")
                }
                guard var scale = Self._indicScale[face]?[top.key] else { return nil }
                if face == "nirmala ui", bold { scale *= 1.076 / 1.086 }
                // Shruti Bold runs 4% narrower than Shruti: dx2 16200736's heading, word starts 111.0 pt apart in Word, 115.9 in ours.
                if face == "shruti", bold { scale *= 0.958 }
                return (face, all * 2 >= letters ? scale : 1)
            }()
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
                   let m = Self._chainFaceLines[chain[-10 - kind].family] {
                    let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
                    s = s.copyWith(ascentOverride: m.0 * multiple * size, descentOverride: m.1 * multiple * size, height: (m.0 + m.1) * multiple, leadingDistribution: .even)
                }
                if kind == -4, let cjk = Self._cjkFaceFamily {
                    RuleTrace.hit("word-east-asian-shape-is-the-cjk-faces-glyph")
                    s = s.copyWith(fontFamily: cjk)
                }
                // (A space set in the ideographs' face keeps the stand-in's width.)
                // (… and no line of its own: the face a space resolves to
                // is not always the ideographs', and its descent made the
                // line taller — zh-1563bd74's footer line, 19.0pt on the
                // Mac against the ideographs' 18.6, and Word's lab `hfl`
                // gives trailing spaces no height at all.)
                if kind == -2 { s = s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + _spaceWidth(style(classed ? RichResolvedFace.characterClass(" ") : 0)) - _spaceWidth(s), height: Self.shadeShows(run.highlight) ? s.height : 0.01) }
                // (Set to the original's widths, the stand-in's own
                // kerning is no part of them: Arial's pair of ones.)
                if kind >= 0, latinFace?.advances != nil || (latinFace?.boldAdvances != nil && s.fontWeight == .bold) { s = s.copyWith(fontFeatures: [FontFeature("kern", 0)]) }
                // (Yu Gothic's Latin, where Word's box lacks the Hangul-named face, carries no pair kerning in the print; 22de7d.)
                if kind >= 0, yuOfMissingHangul, !aumsLatin { s = s.copyWith(fontFeatures: (s.fontFeatures ?? []) + [FontFeature("kern", 0)]) }
                if kind >= 0, let indic, indic.scale != 1, !latinNoScale { s = s.copyWith(scaleX: indic.scale) }
                // (The run's own line is the face's, not the stand-in's, where the face's is the shorter: Aparajita's 1.18 em (a516bfe9: 2.7 to 92.9) where Noto
                // Sans Devanagari's is taller; the joiner above only raises a line.)
                if kind >= 0, let indic, (indic.face == "kokila" && (kokilaLatin || text.unicodeScalars.contains(where: { Self._isIndic($0.value) }))) || (indic.face == "utsaah" && utsaahLatin) || (indic.face == "malgun gothic" && malgunLatin) || (indic.face == "yu gothic" && (aumsLatin || aumsYuInIndic)) || indic.face == "vijaya" || indic.face == "latha" || indic.face == "shonar bangla" || indic.face == "leelawadee ui" || (namedFace != nil && (namedFace != "mangal" || namedKalimati)) || (indic.face == "nirmala ui" && !plainPiece && !p.text.unicodeScalars.contains(where: { Self._tamil.contains($0.value) })), let m = Self._indicLines[(indic.face == "shonar bangla" && (run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold)))) ? "shonar bangla bold" : indic.face], p.style.lineHeightPoints == nil, let size = s.fontSize, size > 0.5 {
                    // (Kokila's line: its own ascent and descent, above and below the baseline, for every run on the line: the stand-ins'
                    // (Carlito's, Noto's) are taller above and set the line 2-3 pt low and 1.4 pt per line too far apart.)
                    // (A multiple under single too: dx2 hin-z20740649's 0.9 lines are 13.5 pt apart in Word's print, Kokila's 15.0 x 0.9.)
                    let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
                    // (Word keeps the baseline where single spacing puts it and gives the multiple's extra below it; a multiple under single is cut from
                    // the top. lab mmatrix2 (2026-11-09): Kokila 18's gap to the next line is 40.8 / 43.9 / 47.0 / 51.1 for a previous 1.0 / 1.15 / 1.3 / 1.5
                    // whatever the next multiple is; `Self._multipleSplit`.)
                    // (Kokila only so far: the other faces' lines were fitted with the extra spread over both sides; each gets the shared split when its own dx2 documents agree.)
                    let split = indic.face == "kokila" || indic.face == "latha" || indic.face.hasPrefix("shonar bangla") ? Self._multipleSplit(ascent: m.0, descent: m.1, multiple: multiple) : (m.0 * multiple, m.1 * multiple)
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
                       return (f.hasPrefix("nirmala ui") && text.unicodeScalars.contains(where: { ($0.value < 0x250 && ($0.properties.isAlphabetic || ($0.value >= 0x30 && $0.value <= 0x39))) || (Self._isIndic($0.value) && !(run.keptXML?.containsSubstring("<w:cs") ?? false)) }))  || f == "arial" }(),
                   !p.text.unicodeScalars.contains(where: { Self._tamil.contains($0.value) }),
                   indic != nil || (!text.unicodeScalars.contains(where: { Self._isIndic($0.value) }) && text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 }) && p.text.unicodeScalars.contains(where: { Self._indic.contains($0.value) }))
                       // (A run of only dandas (। ॥) in a Nirmala UI face has no letter, so no Indic face is chosen for it, and its stand-in's taller line deepened the line 1.2 pt: dx2 bea98273 p5, 15.28 pt against Word's 14.04. The danda is Nirmala's.)
                       || (!text.isEmpty && text.unicodeScalars.allSatisfy({ $0.value == 0x964 || $0.value == 0x965 }) && p.text.unicodeScalars.contains(where: { Self._indic.contains($0.value) && $0.properties.isAlphabetic })),
                   let m = Self._indicLines["nirmala ui"] {
                    let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
                    // (A Nirmala-named run's pieces carry the line's height too; an Arial piece only the ascent/descent split: a line height on its stand-in raised the
                    // line 0.6 pt (dx2 f96948dd 16.57 against Word's 15.96, 1ca6c218's Arial-only title line 32 against 28.6), where the split alone stacks correctly.)
                    let nirmalaNamedRun = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased().hasPrefix("nirmala ui")
                    s = s.copyWith(ascentOverride: m.0 * multiple * size, descentOverride: m.1 * multiple * size, height: nirmalaNamedRun ? (m.0 + m.1) * multiple : nil, leadingDistribution: nirmalaNamedRun ? .even : nil)
                }
                // (A digit, a mark or a no-break space between Nirmala UI's words, in a run whose Latin face is Calibri, is on its line: the line takes Calibri's deeper descent
                // (win 550/2048 = 0.2686 em against Nirmala's 0.251) even where the glyph is drawn in Nirmala; a plain space does not. Word's print of dx2 f4abc45d (Punjabi, 11 pt):
                // lines with an apostrophe, comma, colon, digit or NBSP stand 14.88 apart, the others 14.63; 6af76fa9 likewise.)
                if kind >= 0, plainPiece, indic?.face == "nirmala ui", theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil, let size = s.fontSize, size > 0.5,
                   (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily ?? "").trimmingWhitespace().lowercased() == "calibri",
                   text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 }),
                   !p.text.unicodeScalars.contains(where: { Self._tamil.contains($0.value) }),
                   p.text.unicodeScalars.contains(where: { $0.value >= 0xA00 && $0.value < 0xA80 }),
                   let m = Self._indicLines["nirmala ui"] {
                    let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
                    s = s.copyWith(ascentOverride: m.0 * multiple * size, descentOverride: max(m.1, 550.0 / 2048) * multiple * size, height: (m.0 + max(m.1, 550.0 / 2048)) * multiple, leadingDistribution: .even)
                }
                // (Garamond's Latin beside a Nirmala UI line: a line is its tallest ascent over its deepest descent, and Garamond's own descent (0.2632 em, ascent 0.8618:
                // 1.125 em, Word's 12.36 pt at 11) is deeper than Nirmala's 0.251 where its stand-in's is shallower. Word's Bengali lines with Garamond runs are 14.76 at 11 pt and
                // 14.1 at 10.5 (Nirmala alone 14.63, 13.97). dx2 bea98273.)
                if kind >= 0, theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil, indic == nil, let size = s.fontSize, size > 0.5,
                   (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "garamond",
                   !text.unicodeScalars.contains(where: { Self._isIndic($0.value) }), text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 }),
                   p.text.unicodeScalars.contains(where: { Self._indic.contains($0.value) }), !p.text.unicodeScalars.contains(where: { Self._tamil.contains($0.value) }) {
                    let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
                    s = s.copyWith(ascentOverride: 0.8618 * multiple * size, descentOverride: 0.2632 * multiple * size)
                }
                // (A run of Latin in a face other than Kokila inside a Kokila paragraph: Word stands its line on that face's ascent (above Kokila's) and keeps the
                // Kokila split below it, at a line multiple too (dx2 cbb7ae39's Times New Roman "IRB", lab cb7; its 1.57-line paragraphs: the line is 2.0 pt taller, the
                // extra under the baseline unchanged). White space and the invisible marks beside Kokila text set no line of their own.)
                // (Shonar Bangla beside Arial: the same line, the Latin face's ascent (with its line gap) over the Bengali face's descent; lab stk1.)
                let latinOwner: String? = paragraphLatinOwner
                if kind >= 0, theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, !kokilaLatin || (run.keptXML?.containsSubstring("<w:cs") ?? false), p.style.lineHeightPoints == nil,
                   let latinOwner, let m = Self._indicLines[latinOwner], let size = s.fontSize, size > 0.5,
                   !text.unicodeScalars.contains(where: { Self._isIndic($0.value) }),
                   p.text.unicodeScalars.contains(where: { Self._indic.contains($0.value) }) || (latinOwner == "shonar bangla" && text.unicodeScalars.contains(where: { $0.value == 0xA0 }) && Self._bengaliMissingFace((p.style.mark?.fontFamily ?? "").trimmingWhitespace().lowercased(), document) == "shonar bangla") {
                    // (A real no-break space counts in its own Latin face even in a paragraph with no Bengali letter, where the paragraph's mark is in the missing Bengali face (a line the Shonar one sets): lab cambsp3, Cambria or Calibri 35.2 to 37.2; Cambria-marked lines stay at Cambria's.)
                    // (Latin letters stack only when drawn in a face other than the line's Indic face: a run whose ascii face IS its complex face, such as Shonar Bangla on both, takes that face's own line and adds no Latin ascent; dx2 3f7da49c.)
                    let ownAscii: String = (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
                    let ownComplex: String = (run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
                    let ownIndic: Bool = Self._bengaliMissingFace(ownAscii, document) == "shonar bangla"
                    let ownFace: Bool = latinOwner == "shonar bangla" && ownAscii == ownComplex && ownIndic
                    let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
                    let split = Self._multipleSplit(ascent: m.0, descent: m.1, multiple: multiple)
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
                   !text.unicodeScalars.contains(where: { Self._isIndic($0.value) }), text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 }),
                   Self._latinInNotoTamil(run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? ""),
                   let m = Self._indicLines["mangal"] {
                    RuleTrace.hit("word-latin-run-in-noto-sans-tamil-sets-mangals-line")
                    let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
                    let split = Self._multipleSplit(ascent: m.0, descent: m.1, multiple: multiple)
                    s = s.copyWith(ascentOverride: split.0 * size, descentOverride: split.1 * size, height: (split.0 + split.1) * size / size, leadingDistribution: .even)
                }
                // (Latin letters set in Shruti (the run's own ascii face, the file naming it): Word sets Shruti's own line, 1.68 em, a Latin line
                // that is 13.4 pt in the stand-in at 11 pt against Word's 18.5: sa1 2b3c3b42's header lines in Shruti.)
                if kind >= 0, theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, p.style.lineHeightPoints == nil, let size = s.fontSize, size > 0.5,
                   !text.unicodeScalars.contains(where: { Self._isIndic($0.value) }), text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 }),
                   let face = Optional((run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()), face == "shruti",
                   let m = Self._indicLines[face] {
                    RuleTrace.hit("word-latin-run-in-shruti-sets-shrutis-line")
                    let multiple = p.style.lineSpacing > 0.5 ? p.style.lineSpacing : 1
                    let split = Self._multipleSplit(ascent: m.0, descent: m.1, multiple: multiple)
                    s = s.copyWith(ascentOverride: split.0 * size, descentOverride: split.1 * size, height: (split.0 + split.1) * size / size, leadingDistribution: .even)
                }
                if kind >= 0, let indic, indic.face == "aparajita" || indic.face == "vijaya", let m = Self._indicLines[indic.face], p.style.lineHeightPoints == nil, let size = s.fontSize, size > 0.5 {
                    let multiple = p.style.lineSpacing > 1 ? p.style.lineSpacing : 1
                    s = s.copyWith(height: (m.0 + m.1) * multiple, leadingDistribution: .even)
                }
                if let grown, s.fontSize ?? 0 > 0.5 { s = s.copyWith(height: grown.height) }
                // (Thai in Browallia New or Angsana New: every run, Latin and Thai, carries its face's own split of the line (hhea ascent and
                // descent, by weight), so a line is its tallest ascent over its deepest descent, as Word's: a bold run raises only the lines it is
                // on (xd b96afb37 20.8 pt, e93587db 19.0 beside 20.6), with no stacking of the 0.82-size Thai stand-in on the Latin one.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.lineHeightPoints == nil, s.ascentOverride == nil,
                   let size = s.fontSize, size > 0.5, let h = s.height, let split = Self._thaiLineSplit(s.debugLabel, bold: s.fontWeight == .bold), thaiParagraph {
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
                        let sp = Self._multipleSplit(ascent: t, descent: nat - t, multiple: p.style.lineSpacing)
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
                        let sp = Self._multipleSplit(ascent: t, descent: nat - t, multiple: p.style.lineSpacing)
                        s = s.copyWith(ascentOverride: size * sp.0, descentOverride: size * sp.1, height: nat * p.style.lineSpacing, leadingDistribution: .even)
                    }
                }
                if mixedLatinFaces, kind >= 0, pitch == nil, s.ascentOverride == nil, p.style.lineSpacing > 0, run.ruby == nil, run.emphasis == nil,
                   let size = s.fontSize, size > 0.5, s.height != nil, !(index.map { _verticalBody($0) } ?? false),
                   !text.isEmpty, text.unicodeScalars.allSatisfy({ $0.value < 0x250 || ($0.value >= 0xFB00 && $0.value <= 0xFB06) }),
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
                        let sp = Self._multipleSplit(ascent: asc, descent: nat - asc, multiple: p.style.lineSpacing)
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
                    if h.raise != 0, !_rubyShiftApplies(p, named: named, ruby: run, pitch: pitch) { h.raise = 0 }
                    s = s.copyWith(height: h.height)
                    // (Off a grid the room for the ruby is all over the baseline, not shared with the line's foot:
                    // xb jpn 231fe1 p1 "申請者" under ﾌﾘｶﾞﾅ stands 7pt lower, the next paragraph where it was. Single spacing only: at 1.15 Word's ruby line is shorter, lo-181b561b0a.)
                    if gridPitchIsNil(pitch), p.style.lineHeightPoints == nil, p.style.lineSpacing > 0.995, h.descent > 0, s.ascentOverride == nil, let size = s.fontSize {
                        s = s.copyWith(ascentOverride: size * (h.height - h.descent), descentOverride: size * h.descent, leadingDistribution: .even, debugLabel: (s.debugLabel ?? "") + " ruby-line")
                    }
                    if h.raise != 0, NativeParagraphBuilder.supportsBaselineShift, !(index.map { _verticalBody($0) } ?? false) {
                        s = s.copyWith(baselineShift: (s.baselineShift ?? 0) - h.raise * theme.pixelsPerPoint * scale)
                    }
                } else if mixedRubyRaise != 0, run.ruby == nil, s.fontSize ?? 0 > 0.5 {
                    // (The rest of a one-line paragraph moves with its ruby's base.)
                    s = s.copyWith(baselineShift: (s.baselineShift ?? 0) - mixedRubyRaise * theme.pixelsPerPoint * scale)
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
                        let (aboveReach, belowReach) = Self._shadowReach(sh, pt: pt)
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
                        if !Self.shadeShows(run.highlight) || own > lineSize.size + 0.01 { s = s.copyWith(height: 0.01) }
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
                if !fitBusy, !plainPiece, !latinNoScale { styles[kind] = s }
                return s
            }
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
            func zeroWidth(_ kind: Int) -> TextStyle {
                let s = style(kind < 0 ? 0 : kind).copyWith(letterSpacing: 0)
                return theme.wordRules && s.fontSize ?? 0 > 0.5 && !(kind >= 0 && latinFace?.setsMath == true) ? s.copyWith(height: 0.01) : s
            }
            // (Arabic set to the original face's joining widths, word by
            // word — it parts only at spaces: each word its own span, drawn
            // condensed or widened to the width its joining forms have in
            // that face (`RichResolvedFace.joinedAdvances`), which the line
            // breaking then measures too. Spacing would split a joined
            // word's shaping or, on a zero-width character, be measured and
            // not drawn right to left — zh-d97c5474's lines broke as Word's
            // and stood 47pt past the margin — and on the spaces it ran the
            // words together, Noto Naskh being 11% wider than Arial.)
            let complexFaceOfRun: RichResolvedFace? = {
                guard theme.wordRules else { return nil }
                let normal = _normalChar(document)
                let latin: String? = run.fontFamily ?? named?.char.fontFamily ?? normal?.fontFamily ?? theme.fontFamily
                let complex: String? = run.complexFontFamily ?? named?.char.complexFontFamily ?? normal?.complexFontFamily
                // (No complex-script face named, and Arial Narrow for Latin: Word sets the Arabic in Arial, not in the narrow face.)
                var name = complex ?? latin
                if complex == nil, name?.trimmingWhitespace().lowercased() == "arial narrow" { name = "Arial" }
                return theme.complexFace(name, latin: latin, letters: run.csLetters)
            }()
            let joinedFace: RichResolvedFace? = run.rightToLeft ? complexFaceOfRun : nil
            // A right-to-left space is set in the complex-script face when the document names one apart from the Latin face (b514c2: Arial against the theme's Aptos); the same name for both keeps the Latin table (dx2 Tahoma fa/ur docs).
            let complexSpaceFace: RichResolvedFace? = {
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
                   word.unicodeScalars.contains(where: { $0.value >= 0xD80 && $0.value <= 0xDFF }), let ems = SinhalaAdvances.sum(word) {
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
                if let hebrewFace = joinedFace ?? complexFaceOfRun, numberInComplexFace || word.unicodeScalars.contains(where: { $0.value >= 0x5D0 && $0.value <= 0x5EA }) || word.unicodeScalars.allSatisfy({ $0.value == 0x5F }), let px = s.fontSize, px > 0.5,
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
            var notoStyle: TextStyle? = nil
            var segoeStyle: TextStyle? = nil
            var devanagariStyles: [String: TextStyle?] = [:]
            var spans: [TextSpan] = []
            var start = text.startIndex
            var current: Int? = nil
            func flush(_ end: Substring.Index) {
                guard let kind = current, start < end else { return }
                if yuOfMissingHangul, text[start ..< end].unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x250 }),
                   let y = Self._yuLatinStyle(text[start ..< end], base: joinedScaled(text[start ..< end], style(kind))) {
                    RuleTrace.hit("word-missing-hangul-face-latin-takes-yu-gothic-advances")
                    spans.append(contentsOf: capped(text[start ..< end], run, y))
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
                if kind >= 0, indic?.face == "nirmala ui" || indic?.face == "vijaya", text[start ..< end].unicodeScalars.contains(where: { Self._tamil.contains($0.value) }) {
                    // (Tamil, word by word, at the widths of Nirmala UI's code points: `TamilAdvances`.)
                    let base = style(kind)
                    let tamilCs = run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? ""
                    let spaceInMangal = Self._markInMangal(tamilCs, text[start ..< end])
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
                if kind >= 0, indic?.face == "kokila", kokilaLatin, let px = style(kind).fontSize, px > 0.5, let m = Self._indicLines["kokila"],
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
                            if authored > 0.5, let fitted = _clusterFitted(seg, base: base, authored: authored, table: KokilaAdvances.table(bold: kBold, italic: kItalic), flatScale: Self._indicScale["kokila"]?["D"] ?? 1) {
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
                if kind >= 0, let face = indic?.face, let spaceEm = (face == "vrinda" && (run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold)))) ? 0.3125 : Self._indicSpace[face], let px = style(kind).fontSize, px > 0.5,
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
                    let mSize: Double = Self._wordGridSize(run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize, snap: mangalRegular && theme.wordRules && RichTextTheme.wordWindowsPages) 
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
                                let other = split.rest ? (w0 - measure(split.known, 0)) * (Self._indicScale["mangal"]?["D"] ?? 1) : 0
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
                    for (piece, isIndic) in Self._splitIndicLatin(text[start ..< end]) {
                                                if isIndic, authored > 0.5 {
                            var ws = piece.startIndex
                            while ws < piece.endIndex {
                                var we = ws
                                let sp = piece[ws] == " "
                                while we < piece.endIndex, (piece[we] == " ") == sp { we = piece.index(after: we) }
                                let seg = piece[ws ..< we]
                                if !sp, let fitted = _clusterFitted(seg, base: base, authored: authored, table: shTable, flatScale: Self._indicScale["shonar bangla"]?["B"] ?? 1, conjunctRatio: nil, block: 0x980) {
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
                   !text[start ..< end].unicodeScalars.contains(where: { Self._tamil.contains($0.value) }) {
                    // (Nirmala UI's own Devanagari cluster widths, word by word: `NirmalaAdvances`.)
                    let nBold = run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold))
                    let aSize: Double = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                    let aW: Double = wScale > 0.01 ? wScale : 1
                    let authored: Double = aSize * theme.pixelsPerPoint * scale * aW
                    let base = style(kind)
                    for (piece, isIndic) in Self._splitIndicLatin(text[start ..< end]) {
                                                if isIndic, authored > 0.5 {
                            // (Each word on its own, so the fitted letter spacing never reaches the spaces between words.)
                            var ws = piece.startIndex
                            while ws < piece.endIndex {
                                var we = ws
                                // (In a Bengali face Windows lacks, a no-break space beside a space is drawn in Mangal as the space is: xd 73caaeda's "এবং" + SP + NBSP + "মঙ্গোল", two 6.0 pt spaces in Word, 8.0 pt here.)
                                let missingBn = Self._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") != nil
                                let isGap: (Character) -> Bool = { $0 == " " || (missingBn && $0 == "\u{00A0}") }
                                let sp = isGap(piece[ws])
                                while we < piece.endIndex, isGap(piece[we]) == sp { we = piece.index(after: we) }
                                let seg = piece[ws ..< we]
                                if !sp, let fitted = _clusterFitted(seg, base: base, authored: authored, table: NirmalaAdvances.table(bold: nBold), flatScale: 1, conjunctRatio: nil, block: seg.unicodeScalars.first(where: { $0.value >= 0x900 && $0.value < 0xB00 }).map { $0.value & ~0x7F } ?? 0x900, lowVowelsZero: !nBold, spaceMarks: true) {
                                    spans.append(contentsOf: capped(seg, run, fitted.style))
                                } else if sp, authored > 0.5, let em = Self._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") {
                                    // (A Bengali face Windows lacks: Word draws the space in Mangal, half an em, not the stand-in's 0.26: xd 73caaeda, 6.0 pt at 12 pt.)
                                    RuleTrace.hit("word-missing-bengali-face-space-is-mangal-half-em")
                                    spans.append(contentsOf: capped(seg, run, _indicSpaceStyle(base: base, spaceEm: em, unit: authored)))
                                } else {
                                    spans.append(contentsOf: capped(seg, run, leelawadeeLatin ? Self._arialUnicodeLatin(seg, base: joinedScaled(seg, style(kind))) : joinedScaled(seg, style(kind))))
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
                            if !isIndic, authored > 0.5, theme.wordRules, RichTextTheme.wordWindowsPages, piece.allSatisfy({ $0 == " " }), (run.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased().hasPrefix("nirmala ui"), Self._splitIndicLatin(text[start ..< end]).contains(where: { $0.1 }) {
                                // (Spaces between the Devanagari words of a Nirmala UI run are Nirmala's own when the run's Latin (ascii) face is Nirmala too, 0.2739 em (bold 0.2759; in a run whose ascii face is Arial Word draws the space in Arial, 0.28 em: dx2 b785c95e, xd 1116b68d; lab/metrics/Nirmala_UI*.tsv, lab nirpitch3: Word 3.02 pt at 11 pt, the stand-in's 2.62).)
                                RuleTrace.hit("word-nirmala-space-own-advance")
                                spans.append(contentsOf: capped(piece, run, _indicSpaceStyle(base: st, spaceEm: nBold ? 0.2759 : 0.2739, unit: authored)))
                                continue
                            }
                            // (Spaces between the Bengali words of a run in a face Windows lacks (SolaimanLipi, Nikosh): Word draws them in Mangal, half an em, not the
                            // stand-in's quarter: xd 73caaeda, 6.0 pt at 12 pt, so Word's first line breaks 10 characters earlier than ours did.)
                            if !isIndic, authored > 0.5, theme.wordRules, RichTextTheme.wordWindowsPages, !piece.isEmpty, piece.allSatisfy({ $0 == " " || $0 == "\u{00A0}" }),
                               let em = Self._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? ""),
                               p.text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value <= 0x9FF && $0.properties.isAlphabetic }) {
                                RuleTrace.hit("word-missing-bengali-face-space-between-words-is-mangal-half-em")
                                // (And it lifts the line to Mangal's 1.241 + 0.438 em as a mark does: the line of letters and spaces alone steps 20.2 in Word, 16 in ours.)
                                if !_isSolaimanLipi(run, named, document), devanagariStyles["mangal"] == nil, let m = Self._indicLines["mangal"] {
                                    devanagariStyles["mangal"] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: m.0, descent: m.1)
                                }
                                let spaceBase = !_isSolaimanLipi(run, named, document) ? (devanagariStyles["mangal"].flatMap { $0 } ?? st) : st
                                spans.append(contentsOf: capped(piece, run, _indicSpaceStyle(base: spaceBase, spaceEm: em, unit: authored)))
                                continue
                            }
                            spans.append(contentsOf: capped(piece, run, leelawadeeLatin ? Self._arialUnicodeLatin(piece, base: joinedScaled(piece, st)) : joinedScaled(piece, st)))
                        }
                    }
                    start = end
                    return
                }
                if kind >= 0, indic?.face == "nirmala ui", Self._splitIndicLatin(text[start ..< end]).count > 1 {
                    // (Word builds each line from the tallest ascent and the deepest descent of the faces on it: the Latin, digits, spaces
                    // and marks between Nirmala UI's words are Arial's and carry no Nirmala line of their own.)
                    for (piece, isIndic) in Self._splitIndicLatin(text[start ..< end]) {
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
                    spans.append(contentsOf: capped(text[start ..< end], run, Self._leelaLatinStyle(text[start ..< end], base: joinedScaled(text[start ..< end], style(kind)))))
                    start = end
                    return
                }
                // (A space in a run of its own whose Latin face is Mangal, in a Devanagari paragraph: Word draws it in Mangal, 0.5 em, 5.52 pt
                // at 11 pt, where the stand-in's Latin space is 3.1; dx2 2db27e2d's "है; उदाहरण", the space after the ";".)
                if kind >= 0, mangalLatinSpace, text[start ..< end].allSatisfy({ $0 == " " || ($0 == "\u{00A0}" && spaceBeforeDanda) }) {
                    RuleTrace.hit("word-mangal-latin-run-space-is-half-em")
                    let base = style(kind)
                    let authored = Self._wordGridSize(run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize, snap: true) * theme.pixelsPerPoint * scale
                    spans.append(contentsOf: capped(text[start ..< end], run, _indicSpaceStyle(base: base, spaceEm: 0.5, unit: authored)))
                    start = end
                    return
                }
                // (A run with no w:cs in an Indic paragraph, Arial Unicode MS in the ascii slot: Word draws its Latin, digits and marks in Yu Gothic; dx2 fb94294e.)
                if kind >= 0, aumsYuInIndic, let y = Self._yuLatinStyle(text[start ..< end], base: joinedScaled(text[start ..< end], style(kind))) {
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
                        if lat, let y = Self._yuLatinStyle(piece, base: st) {
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
            var offset = base
            var i = text.startIndex
            var compatJoinerAfter: TextStyle? = nil
            // (Measured as shown: a run in capitals (`capped`) is spaced,
            // kerned and put on the grid by its capitals — 60810's titles,
            // "Connection to global talent programmes/R200" in caps, lost
            // "TA" and "LT"'s kerning and wrapped a line PowerPoint fits.)
            let shownCaps = theme.measuresShownCaps && (run.caps || ((named?.char.caps ?? false) && !run.off.contains(.caps)))
            func shown(_ c: Character) -> Character {
                guard shownCaps else { return c }
                let up = String(c).uppercased()
                return up.utf16.count == String(c).utf16.count && up.count == 1 ? Character(up) : c
            }
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
                let ch: Character = shown(text[i])
                let after = text.index(after: i)
                let following = (after < text.endIndex ? text[after] : next).map(shown)
                // (An ideographic space on a line of spaces alone is set
                // as the mark is, in the run's Latin face: see `lineSize`.)
                let ea = theme.wordRules && RichLayout.isEastAsian(ch, hinted: hinted || (eastDash && ch == "\u{2014}")) && !(ch == "\u{3000}" && lineSize?.blank == true)
                    && !(latinDash && ch == "\u{2013}")
                    // (Nor a "×" or "÷", Latin-1's signs, which Word sets in the hAnsi
                    // face as it does the dash: zh-7a16a243's unhinted "×" in a run of
                    // 標楷體 over its heading style's Arial hAnsi is Arial's 9.34pt and
                    // half the grid's 1.0076 in Word for Windows' print, 9.9 — ours set
                    // 標楷體's half em, 8.5, and the line "…672％)，然上開「允建樓地板面"
                    // took the "積" Word sends down.)
                    && !(latinDash && RichTextTheme.wordWindowsPages && (ch == "\u{00D7}" || ch == "\u{00F7}"))
                var kind = ea ? -1 : (classed ? RichResolvedFace.characterClass(ch) : 0)
                // (Circles, squares and stars in an East Asian run are the East Asian face's glyph
                // — an em wide, 0.86 across — not the Latin stand-in's small one: kind -4.)
                if hyphenFace != nil, ch == "-" { kind = -1000 }
                if ea, eastDash, ch == "\u{2014}" { kind = -5; RuleTrace.hit("word-em-dash-drawn-in-east-asian-hansi-face") }
                if ea, theme.wordRules, RichTextTheme.wordWindowsPages, Self._cjkFaceFamily != nil, let u = ch.unicodeScalars.first?.value,
                   (0x25A0 ... 0x25EF).contains(u) || u == 0x2605 || u == 0x2606 { kind = -4 }
                // (A card suit in a run (East Asian by its hint) whose Latin face is Malgun Gothic itself (a theme's; Nanum Barun's suits are not an em: b60ada18) is that face's glyph, an em wide, not
                // the stand-in's 0.66 em: xd 89a3482a's "♣♣♣" are Malgun 12 pt wide each in the print, ours 7.9, and "수" after them stayed on the line.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile, Self._cjkFaceFamily != nil,
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
                        } else if chainAt == nil, let w = Self._cambriaMathOpeners[u] {
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
                } else if theme.wordRules, RichTextTheme.wordWindowsPages, (ctx.before == "." && ch == "." && !(Self._stopRunFitsAfterSpace(Array(p.text.utf16), at: offset, measure: { run in let t = TextPainter(text: TextSpan(text: run, style: style(kind)), textDirection: .ltr); t.layout(minWidth: 0, maxWidth: 100_000); defer { t.dispose() }; return t.width }, width: _px(textWidth))) && !(Self._stopRunAfterWordFits(Array(p.text.utf16), at: offset, measure: { run in let t = TextPainter(text: TextSpan(text: run, style: style(kind)), textDirection: .ltr); t.layout(minWidth: 0, maxWidth: 100_000); defer { t.dispose() }; return t.width }, width: _px(textWidth)))) || (!document.usesEastAsianLayout && (ctx.before == "…" || ch == "…") && (ctx.before == "." || ctx.before == "…") && (ch == "." || ch == "…") && Self._stopRunWidth(Array(p.text.utf16), at: offset, size: style(kind).fontSize ?? 12) > textWidth), document.usesEastAsianLayout || !ctx.dotsAttached {
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
                          Self._fullwidthOperatorHeld(bv, v) {
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
                          Self._hangulHeldPair(bv, v) || koreanTokenJoins.contains(offset) {
                    // (Word keeps a Hangul word whole at the line end unless the paragraph's word wrap is off
                    // (census of dx2 ko: 20bb671d's "학회에서", "제1저자,"); with it off it parts mid-word.)
                    RuleTrace.hit("hangul-word-held-whole")
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    ctx.inserts.append(offset)
                } else if theme.wordRules || theme.officeLatinBreaks, let b = ctx.before,
                          Self.joinsLatin(b, ch, eastAsian: document.usesEastAsianLayout) {
                    flush(i)
                    spans.append(TextSpan(text: "\u{2060}", style: zeroWidth(current ?? kind)))
                    ctx.inserts.append(offset)
                } else if theme.wordRules, document.usesEastAsianLayout, ch == ">", let b = ctx.before,
                          let v = b.unicodeScalars.first?.value, (0x3400...0x9FFF).contains(v) || (0xF900...0xFAFF).contains(v) || v >= 0x20000,
                          !Self._traditionalChinese(document) {
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
                } else if theme.wordRules, !document.usesEastAsianLayout, let b = ctx.before, Self._breaksAfterHyphen(ctx.beforeBefore, b, ch) {
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
                   Self._notoCompatibility.contains(u),
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
                    if let b = ctx.before, Self.isEastAsian(b, hinted: true) ? !Self._openingMarks.contains(b)
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
                        if let b = ctx.before, Self.isEastAsian(b, hinted: true) ? !Self._openingMarks.contains(b)
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
                if theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, u >= 0x20, u < 0x250, ch.unicodeScalars.count == 1, !Self._setsNoLine(ch), ch != " ", ch != "\u{A0}",
                   !(ctx.before.map { ($0.unicodeScalars.first?.value ?? 0x3000) < 0x250 && !($0 == " " && ctx.beforeBefore == nil) } ?? false), _yuLatinOfMissingHangulFace(run, named, document), !document.hasIndicText, !aumsLatin {
                    if devanagariStyles["missingHangulYu"] == nil {
                        devanagariStyles["missingHangulYu"] = _lineJoiner(run, named, style(-1), p.style, pitch, scale, ascent: Self._indicLines["malgun gothic"]!.0, descent: 0.492)?.copyWith(debugLabel: "yu-joiner")
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
                   let metrics = Self._indicLines["malgun gothic"] {
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
                if theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, !Self._isIndic(u) || u == 0x964 || u == 0x965,
                   !ch.isWhitespace,
                   u != 0x200B, u != 0x200C, u != 0x200D, u != 0x2060, u != 0xFFFC,
                   !(ctx.before.map { !$0.isWhitespace && !($0.unicodeScalars.first.map { Self._isIndic($0.value) } ?? false) } ?? false),
                   Self._markInMangal(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "", text) || ((_isSolaimanLipi(run, named, document) || (ctx.splittingMark && p.style.lineSpacing > 1.0 && p.style.lineHeightPoints == nil)) && _asciiRunInMissingBengaliFace(run, named, document, text, p.text)),
                   let metrics = Self._indicLines["mangal"] {
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
                if namedFace == "mangal", theme.wordRules, RichTextTheme.wordWindowsPages, !p.text.unicodeScalars.contains(where: { Self._isIndic($0.value) }), let u = ch.unicodeScalars.first?.value, !Self._isIndic(u), !ch.isWhitespace,
                   u != 0x200B, u != 0x200C, u != 0x200D, u != 0x2060, u != 0xFFFC,
                   !(ctx.before.map { !$0.isWhitespace } ?? false),
                   let metrics = Self._indicLines["mangal"] {
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
                        let malgun = Self._indicLines["malgun gothic"] ?? (1.288, 0.442)
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
                   let fb = Self._compatFormFallbackLine(u),
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
                let insideWide = !wideIndicWords.isEmpty && wideIndicWords.contains { offset > $0.lowerBound && offset < $0.upperBound }
                // (Myanmar: the line joiner goes before each consonant, so every line that holds Myanmar letters has Myanmar Text's line.)
                let myanmarJoin = indic?.face == "myanmar text" && (ch.unicodeScalars.first.map { $0.value >= 0x1000 && $0.value <= 0x1021 } ?? false)
                if theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, Self._isIndic(u) || myanmarJoin,
                   myanmarJoin || insideWide || !(ctx.before?.unicodeScalars.first.map { Self._isIndic($0.value) || $0.value == 0x200D || $0.value == 0x200C } ?? false) {
                    let face0 = indic?.face
                    // (Shonar Bangla Bold is its own face in Word: 1721+978 of 2048 against the regular's 1655+996.)
                    let face = (face0 == "shonar bangla" && (run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold)))) ? "shonar bangla bold" : face0
                    if let face, let metrics = Self._indicLines[face] {
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
                let narrowFamily = run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                   ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily
                // (Asked once per family, not once per character.)
                let narrowQuotes: Bool
                if let known = _narrowQuoteMemo[narrowFamily ?? ""] {
                    narrowQuotes = known
                } else {
                    narrowQuotes = theme.faceResolver?(narrowFamily, true)?.otherAdvances?[0x201D] != nil
                    _narrowQuoteMemo[narrowFamily ?? ""] = narrowQuotes
                }
                let quote = ea && fullQuotes && (ch == "\u{201C}" || ch == "\u{2018}" || ch == "\u{201D}" || ch == "\u{2019}")
                    && !narrowQuotes
                // (None where the face's own quote is the em to a hair: Starling
                // FangSong's is 15.99997 of 16, and a blank of that hair sent
                // the squeeze the line fitting asked of an opening quote into a
                // joiner that cannot be narrower than nothing — zh-8186c98d's
                // "…中的标准计" lost its "计" on Linux.)
                let blank = quote ? max(0, em - _glyphWidth(style(kind), ch)) : 0
                let blankShown = blank > _px(0.01) ? blank : 0
                var led = false
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
                        (0x0E01 ... 0x0E5B).contains(pb), (0x0E01 ... 0x0E5B).contains(pc) {
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
                        b != " ", b != "\t", b != "\n", b != "\u{2028}", b.isASCII || (following == "\t" && Self.isEastAsian(b, hinted: false)),
                        (p.style.alignment == .justify || !p.style.tabStops.contains(where: { s in
                            let edge = textWidth + _px(_listIndents(p, document)?.left ?? p.style.indentLeft)
                            return s.alignment == .right && !(s.leader ?? "none").isEmpty && s.leader != "none"
                                && _px(s.position) > edge + 0.5 && _px(s.position) <= edge + _px(Self._tabPastMargin) + 0.5
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
                @inline(never) func _sblk1() {
                if ctx.afterHeld, ch != " ", !(breaksAtQuotes && !lineRulesOff && Self._closingMarks.contains(ch)) {
                    flush(i)
                    // (In the held spaces' own style, not the East Asian
                    // text's after them: there its glyph is the Latin base
                    // family's, whose ascent and descent split the em
                    // otherwise than the CJK face's, and the line grew
                    // 0.9pt at 12pt — zh-799c91cd's page 1 lost a line.)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(ctx.heldKind ?? current ?? kind)))
                    ctx.inserts.append(offset)
                    ctx.afterHeld = false
                } else if theme.wordRules, (ctx.before == "\u{2014}" && ch.isASCII && ch.isNumber && ctx.beforeBefore.map { $0.isASCII && $0.isNumber || Self._closingMarks.contains($0) } == true)
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
                } else if theme.wordRules, breaksAtQuotes, !lineRulesOff, ctx.before == " ", Self._closingMarks.contains(ch) {
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
                            || ctx.beforeBefore.map { !$0.isASCII && Self.isEastAsian($0, hinted: false) } == true {
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
                          ch == "%" || ch == "‰" || ch == "℃" || Self._closingMarks.contains(ch) {
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
                          document.eastAsiaLanguage?.hasPrefix("ja") != true, let b = ctx.before, (b.unicodeScalars.first?.value ?? 0) >= 0x3040, !Self._openingMarks.contains(b) {
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
                } else if plainNoLineRules, ch == "\u{30FB}", let b = ctx.before, (b.unicodeScalars.first?.value ?? 0) >= 0x3040, !Self._openingMarks.contains(b) {
                    // (A plain file with no line rules (Pandoc's en-US) opens a line with the middle dot too:
                    // jpn-z21601833-4e6465 p6 ends "…完全な終了" and starts "・完全な静止を取らない".)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
                    ctx.inserts.append(offset)
                } else if pausesOpenLines, ch == "\u{3001}" || ch == "\u{3002}" || ch == "\u{FF09}", let b = ctx.before, !Self._closingMarks.contains(b) {
                    // (A full-width ")" too: 8787f4 p8 ends "…（ドーシ, 1982" and opens the next line with "）。".)
                    // (Where the pause rule holds Word opens a line with 、 or 。 rather than
                    // hang it or carry the character before it down: lab `sqreal`.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
                    ctx.inserts.append(offset)
                } else if RichTextTheme.wordWindowsPages, theme.wordRules, (document.compatibilityMode ?? 12) == 14, document.characterSpacingControl == "compressPunctuation",
                          document.markSqueezeEm == 0, ch == "\u{FF0C}" || ch == "\u{3001}" || ch == "\u{3002}", let b = ctx.before, !Self._closingMarks.contains(b) {
                    // (Under compressPunctuation at compat 14 with no language or ko-KR, whose marks Word never
                    // squeezes (glyph advances 12.0 of 12.0 and 16.0 of 16.0, lab comma-hang7 v6/v8), Word opens
                    // a line with the mark rather than hang it or carry the character before it down.)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
                    ctx.inserts.append(offset)
                } else if (kinsokuOff || plainNoLineRules || (theme.wordRules && (ch == "\u{3001}" || ch == "\u{3002}") && !hanJoins.contains(offset) && Self._dunhaoMayStart(run, document, named: named)) || (RichTextTheme.wordWindowsPages && theme.wordRules && document.defaultLangXML == nil && document.eastAsianDefaultFaceIsLatin && (!document.bodyStatesLang || !Self._runStatesLang(run, named)))) && !breaksAtQuotes, let b = ctx.before,
                          Self._closingMarks.contains(ch) || Self._latinCloser(b, ch) || Self._plainMayStart(b, ch)
                            || (ch != " " && (Self._openingMarks.contains(b) || Self._latinOpener(b, ch))
                                && Self._plainOrKinsoku(plainNoLineRules, kinsokuOff, Self._eastAsianLineRules(run, document, named: named)) && Self._plainOpenerBreak(plainNoLineRules && !kinsokuOff && !openerBeforeLatin, ch)) {
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
                          document.hasKana || document.eastAsiaLanguage?.hasPrefix("ja") == true, Self._openingMarks.contains(b), document.characterSpacingControl?.hasPrefix("compressPunctuation") ?? false,
                          (ch.unicodeScalars.first?.value ?? 0) >= 0x2E80, adjust[-(offset + 1)] == nil {
                    // (Under compressPunctuation Word may end a line on an opening
                    // mark, squeezed by up to half its em: labs opn1 and opn11, 8787f4.
                    // The fit decides, and a mark it would carry gets the key -(offset+1).)
                    flush(i)
                    spans.append(TextSpan(text: "\u{200B}", style: zeroWidth(current ?? kind).copyWith(height: 0.01)))
                    ctx.inserts.append(offset)
                } else if breaksAtQuotes, let b = ctx.before, !(Self._closingQuote(ch) && b.isASCII && b != " " && b != "\n"),
                          // (A closing quote right after an ASCII character is no break, whatever the East Asian
                          // rules say: xa gv-690391482c (en-GB East Asian language, usesEastAsianLayout) keeps
                          // "individuals.”" whole in Word's print, ours sent the quote down alone.)
                          Self._breaksBetween(b, ch, percentStarts: percentStarts, timesEastAsian: hinted, shapesPart: (document.compatibilityMode ?? 12) >= 15 || RichTextTheme.wordWindowsPages, latinQuotes: theme.wordRules && !hinted) || (lineRulesOff && !(Self._hangulSyllable(b) && (ch == ")" || ch == "." || ch == "," || ch == "]")) && (Self._closingMarks.contains(ch) || Self._latinCloser(b, ch)))
                            || (theme.wordRules && Self._closingQuote(ch) && (kinsokuOff && hinted && RichTextTheme.wordWindowsPages || !Self._eastAsianLineRules(run, document, named: named)))
                            // (And end one with an opening mark, where it is
                            // `w:kinsoku` 0 that turns them off in text of an
                            // East Asian language: zh-72da925e (zh-TW) ends
                            // a line "…（下稱「" in Word's print, "中" opening
                            // the next. Not where the language is not one —
                            // zh-c5b5087b's en-US carries "（" over.)
                            || ((kinsokuOff || plainNoLineRules) && ch != " " && (Self._openingMarks.contains(b) || Self._latinOpener(b, ch)) && Self._plainOrKinsoku(plainNoLineRules, kinsokuOff, Self._eastAsianLineRules(run, document, named: named)) && Self._plainOpenerBreak(plainNoLineRules && !kinsokuOff && !openerBeforeLatin, ch))
                            // (A full-width opening quote the same: zh-b00fef0d's "…其中" sends "“1" down whole,
                            // the quote unable to stay alone at the line's end 12pt over.)
                            || (kinsokuOff && RichTextTheme.wordWindowsPages && ch != " " && (b == "\u{201C}" || b == "\u{2018}") && runHinted(atOffset: offset - 1) && Self._eastAsianLineRules(run, document, named: named))
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
                var extra = led ? min(0, blankShown + (adjust[offset] ?? 0)) : adjust[offset] ?? 0
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
                let nbspHAnsi = theme.wordRules && RichTextTheme.wordWindowsPages && !ea && ch == "\u{00A0}" && latinFace?.isEastAsian == true
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
                if theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value,
                   u >= 0xAC00 && u <= 0xD7A3 {
                    let g = _glyphWidth(style(kind), ch)
                    // (A face may carry its own Hangul em under U+AC00 of otherAdvances: NanumGothic 0.94.)
                    let hEm = (theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                                   ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.otherAdvances?[0xAC00]).map { $0 * em * wScale } ?? em * wScale
                    // (A character scale, w:w, narrows the syllable too: dx2 211f43df's 95% Gulim 11 pt is 10.44 in Word's print, 11.04 here.)
                    if g > 0.5, hEm < em * wScale ? abs(g - hEm) > 0.01 : g < hEm - 0.01 {
                        RuleTrace.hit("hangul-syllable-is-an-em")
                        extra += hEm - g
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
                if ea, let u = ch.unicodeScalars.first?.value, u >= 0xF900, u <= 0xFAFF, !Self._notoCompatibility.contains(u),
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
                let malgunDigit: Bool = {
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
                let jisLatin1: Bool = _jisLatin1Symbol(ch, theme: theme, run: run, named: named, document: document, hint: hint)
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
                @inline(never) func _sblk2() {
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
                        if theme.wordRules, let from = kernsFrom, from > 0, points >= from, let pairs, after < text.endIndex,
                           let v = shown(text[after]).unicodeScalars.first?.value, v >= 0x20, v <= 0x7E, let pair = pairs[u << 8 | v] {
                            target += pair * px / (face.sizeScale * classScale)
                        }
                        // (On the print's grid too, kerned as the stand-in
                        // kerns, where the theme has one: `advanceGrid`.)
                        if let grid = theme.advanceGrid, grid > 0 {
                            let size = run.fontSize ?? named?.char.fontSize ?? theme.fontSize
                            let kerns = (run.kerningFrom ?? named?.char.kerningFrom).map { $0 > 0 && size >= $0 } ?? false
                            if kerns, let following { target += _pairAdvance(s, ch, following) - _glyphWidth(s, ch) }
                            let g = grid * theme.pixelsPerPoint * scale
                            if g > 0 { target = (target / g).rounded() * g }
                        }
                        extra += target - _glyphWidth(s, ch)
                    }
                } else if !ea, theme.wordRules, RichTextTheme.wordWindowsPages, let u = ch.unicodeScalars.first?.value, u == 0x2266 || u == 0x2267,
                          ch.unicodeScalars.count == 1, let w = RichLayout._cambriaMathOpeners2[u],
                          text[..<i].last.map({ $0.isASCII && ($0.isLetter || $0.isNumber) }) == true {
                    // (Cambria has no "≦" or "≧": Word for Windows sets them in Cambria Math, 0.7471 em wide;
                    // after a Latin letter or digit; after an ideograph it stays the East Asian face's full width (lab c2301a p3 "で≦2fm"). The fallback face's 0.84 pushed jpn-z21601833-c2301a's "…CHSH≦2、完" a character over.)
                    extra += w * em - _glyphWidth(style(kind), ch)
                } else if !ea, let grid = theme.advanceGrid, grid > 0, latinFace?.advances == nil, ch != "\t", !ch.isNewline,
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
                } else if !ea, !nbspHAnsi, let u = ch.unicodeScalars.first?.value,
                          let face = (u >= 0x80 && highFace?.otherAdvances?[u] != nil ? highFace : nil) ?? latinFace, face.otherAdvances != nil,
                          // (A letter with its marks, where the table has each:
                          // Thai's "ต่", "คำ" — `OfficeFonts.browalliaAdvances`.)
                          ch.unicodeScalars.count == 1 || (u >= 0x0E00 && u < 0x0E80 && ch.unicodeScalars.allSatisfy { face.otherAdvances?[$0.value] != nil }),
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
                    let table = s.fontWeight == .bold ? face.boldOtherAdvances : face.otherAdvances
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
                }
                _sblk2()
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
                    if theme.wordRules, document.usesEastAsianLayout || (document.autoSpacesWithoutFELayout && document.eastAsianLineRules && (document.defaultLangXML?.containsSubstring("w:eastAsia=\"") == true || ((document.compatibilityMode ?? 15) < 15)) && RichTextTheme.wordWindowsPages), !besideRaised, !(RichTextTheme.wordWindowsPages && document.skipsAutoSpace), Self._autoSpaced(ch, following, p.style, compat: document.compatibilityMode ?? 12),
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
                    } else if ea, closes, Self.closesUp(ch, following, centred: document.marksCentred)
                                // (A middle dot after a closing mark closes it up too, in kana text at compat 15 on a grid: lab
                                // `jis4051`, Word for Windows, sets "」・" with the 」 at its half like "」。".)
                                || (following == "\u{30FB}" && Self._closingBracketMarks.contains(ch) && RichTextTheme.wordWindowsPages && theme.wordRules
                                    && (document.compatibilityMode ?? 12) >= 15 && document.lineGridPitch != nil
                                    && (document.hasKana || document.eastAsiaLanguage?.hasPrefix("ja") == true))
                                // (And a middle dot before an OPENING mark sits at its half, in a Japanese document on a line grid:
                                // xb jpn-z23002680-771abc's "・『フランク" sets ・ 5.3 pt at 10.56 (『 at +0.5 em), so its line holds
                                // "年代" where ours broke after "年"; xd a91d8fed (compat 14), f42177d2 and jpn 1e9281 agree; a
                                // Pandoc file with no grid (4e6465) keeps the whole em.)
                                || (ch == "\u{30FB}" && Self._openingMarks.contains(following) && RichTextTheme.wordWindowsPages && theme.wordRules
                                    && document.lineGridPitch != nil && (document.hasKana || document.eastAsiaLanguage?.hasPrefix("ja") == true))
                                // (The quote's own run says whether it is full-width, where the mark
                                // ends its run: zh-3ab8a2fb's "，" unhinted before a "“" hinted East
                                // Asian closes up, 7.13 in Word's print, and its line takes "机".)
                                || (fullQuotes && !narrowQuotes && (following == "\u{201C}" || following == "\u{2018}") && Self._closingMarks.contains(ch)
                                    && Self.isEastAsian(following, hinted: after < text.endIndex ? hinted : runHinted(atOffset: base + text.utf16.count)))
                                // (And before a full-width closing quote, mid-line with room as well: lab `sqp`
                                // (Word for Windows, zh-424775e4's p5 line, SimSun 12, kerned) sets "。”" 6 + 12 in
                                // modes 12 and 15 and under doNotCompress alike, and takes "机，" 6pt sooner than ours
                                // did with the "。" a whole em; the "。" not centred, as a closing bracket's.)
                                || (fullQuotes && !narrowQuotes && (following == "\u{201D}" || following == "\u{2019}") && Self._closingMarks.contains(ch)
                                    && !(document.marksCentred && "，。、；：！？".contains(ch))
                                    && Self.isEastAsian(following, hinted: after < text.endIndex ? hinted : runHinted(atOffset: base + text.utf16.count)))
                                // (Not a face's own narrow quote, which has no
                                // blank to give: zh-0aac9d1a's Arial Unicode MS
                                // "黑名单”。" keeps its 5.52pt "”" before the "。" in
                                // Word's print; ours took half an em off it, all of
                                // it, and the line took a "省" Word wraps.)
                                || (fullQuotes && !narrowQuotes && (ch == "\u{201D}" || ch == "\u{2019}") && Self.isEastAsian(ch, hinted: hinted)
                                    && (Self._closingMarks.contains(following) || Self._openingMarks.contains(following)
                                        || ((following == "\u{201C}" || following == "\u{2018}") && Self.isEastAsian(following, hinted: hinted)))) {
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
                if theme.wordRules, RichTextTheme.wordWindowsPages, kind == -1, let following, ch.unicodeScalars.count == 1, following.unicodeScalars.count == 1,
                   let u = ch.unicodeScalars.first?.value, let v = following.unicodeScalars.first?.value, u >= 0x3040, u < 0x3100, v >= 0x3000, v < 0x3100,
                   let pair = Self.yuMinchoKerns[u << 16 | v],
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
                    let a: Double? = u0 == 0x20 ? (aumsLatin || !hangulBeside ? 584.0 / 2048 : 0.5) : (u0 == 0x28 ? Optional(791.0 / 2048) : (bold ? Self.yuGothicBold : Self.yuGothicRegular)[u0].map { Double($0) / 2048 })
                    // (The size-compensated stand-in grows lowercase letters' style size; the advance is the nominal size's, the capitals' kind.)
                    if let a, let px = style(classed ? RichResolvedFace.characterClass("H") : 0).fontSize, px > 0.5 {
                        RuleTrace.hit("word-missing-hangul-face-latin-takes-yu-gothic-advances")
                        extra = a * px - _glyphWidth(s, ch) + (adjust[offset] ?? 0)
                    }
                }
                _sblk3()
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
                    } else if theme.wordRules, RichTextTheme.wordWindowsPages, Self._afterBreakRun(Array(p.text.utf16), offset) {
                        // (A space run that opens a line after a manual break: a figure space of the space's width, which the engine keeps at a line start where a no-break space collapses.)
                        spans.append(TextSpan(text: "\u{00A0}", style: s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra + _glyphWidth(s, " ") - _glyphWidth(s, "\u{00A0}"))))
                    } else {
                        var heldStyle = extra != 0 ? s.copyWith(letterSpacing: (s.letterSpacing ?? 0) + extra) : s
                        // (A tab held as a no-break space sets no line beside text, as a run of tabs sets none: sa1 7770c637's
                        // justified contents line "I.<tab>RESUMEN…", its tab in Calibri 11 among 9pt Courier New raised 2pt, is
                        // 24.36 to the next line in Word's print as every other contents line; its held tab broke the line's
                        // strut and stood it on Calibri's 11pt line, 25.89. Shaded, it keeps its box to paint the shade.)
                        if theme.wordRules, ch == "\t", s.fontSize ?? 0 > 0.5, !Self.shadeShows(run.highlight),
                           p.text.contains(where: { !$0.isWhitespace && $0 != "\u{FFFC}" }),
                           Self._tabBiggerThanText(run.fontSize ?? named?.char.fontSize ?? theme.fontSize, p, named?.char.fontSize ?? theme.fontSize) {
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
                } else if ea, theme.wordRules, (style(kind).fontWeight == .bold || theme.faceResolver?(run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.otherAdvances?[0x2160] == nil), let cjk = Self._cjkFaceFamily, let u = ch.unicodeScalars.first?.value, (0x2160 ... 0x217F).contains(u) || u == 0x25C8 {
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
                          // (General Punctuation only, not the invisible format marks U+2028-202F and U+205F-206F (the engine's own word joiner U+2060 is one): Word's prints draw math and enclosed symbols (⌈ ① in 0d8cbc, 27083953) in Cambria Math, and U+2011 as a plain hyphen, not in the East Asian face; a form check box is a drawn box. A mark the run's Latin face lacks, by that face's cmap (Self._latinSymbolCmap, from the Windows Word box); a face not in the table keeps only ※.)
                          Self._latinFaceLacks(run.fontFamily ?? named?.char.fontFamily ?? "", u) ?? (u == 0x203B),
                          let cjk = Self._cjkFaceFamily {
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
                } else if ea, theme.wordRules, RichTextTheme.wordWindowsPages, ch == "\u{203B}", let cjk = Self._cjkFaceFamily,
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
                } else if ea, theme.wordRules, let cjk = Self._cjkSymbolFamily, Self._cjkSymbols.contains(ch) {
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
                    if ch == " ", kind >= 0, indic?.face == "kokila", kokilaLatin, let px = s.fontSize, px > 0.5, Self._indicLines["kokila"] != nil {
                        s = _kokilaLatinStyle(" ", base: s, px: px)
                    } else if ch == " ", kind >= 0, indic?.face == "shonar bangla", let px = s.fontSize, px > 0.5 {
                        // (Shonar Bangla's own space, 0.2065 em, for a space the fit cut out of its run.)
                        let authored = (run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
                        s = _indicSpaceStyle(base: s, spaceEm: 0.2065, unit: authored)
                    } else if ch == " ", kind >= 0, let face = indic?.face, face != "kokila",
                              // (A space the fit cut out of a danda-and-space run in a missing Bengali face: the fit's extra IS its pad up to Mangal's half em (lab left0, 60.3 units), so the pad is not added a second time: the space was 8.5 pt, 5.5 in Word.)
                              !(extra != 0 && Self._missingBengaliSpaceEm(run.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "") != nil),
                              let spaceEm = (face == "vrinda" && (run.bold || ((named?.char.bold ?? false) && !run.off.contains(.bold)))) ? 0.3125 : Self._indicSpace[face],
                              let px = s.fontSize, px > 0.5 {
                        // (The same for the faces whose space is their own, Mangal, Vrinda, Utsaah: one path, `_indicSpaceStyle`.)
                        let authored = Self._wordGridSize(run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize, snap: face == "mangal" && theme.wordRules && RichTextTheme.wordWindowsPages) * theme.pixelsPerPoint * scale
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
