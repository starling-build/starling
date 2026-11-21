// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paragraph": moved out of RichLayout.swift by test/tools/split-richlayout.py (a pure move, so that
// the parts compile side by side).

import Flutter
import FlutterSwiftBridge
import Foundation

extension RichLayout {

    /// Word for Windows at compat 14 and under honours a tab stop past the margin (lab tabpast14; sa1 0058af10, dx2 e1996ca7 and
    /// 9f798d64, xa gv-0de3e9bcf1): the text after it ends AT the stop and stays on the line. The engine fits a line against the
    /// margin, so the lines are broken by the clamped layout first (it matched Word's breaks in all four); where that is ONE line
    /// the paragraph is laid out again with room past the margin, the stops as written.
    func _layoutParagraphOnce(_ i: Int, _ p: RichParagraph, _ document: RichDocument) {
        _pastNeed[i] = nil
        _pastLeft[i] = nil
        _pastWiden = nil
        _topLift = nil
        _vrubyPlain = nil
        _layoutParagraphBody(i, p, document)
        // (Word's top alignment is per line: a smaller run stands higher only on a line that holds a bigger one. The probe layout above
        // gives the line starts; the paragraph is laid out again with each line's biggest size. Only top-aligned mixed-size paragraphs.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.lineHeightPoints == nil,
           p.style.eastAsian["w:textAlignment"] == "top", p.runs.count > 1, let painter = _painters[i] {
            let named = _named(p, document)
            func sizePt(_ r: CharStyle) -> Double { r.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize }
            let u16 = Array(p.text.utf16)
            var spans: [(from: Int, to: Int, size: Double)] = []
            var at = 0
            for r in p.runs {
                defer { at += r.length }
                guard r.length > 0, r.style.script == .normal, at + r.length <= u16.count,
                      u16[at..<(at + r.length)].contains(where: { $0 != 9 }) else { continue }
                spans.append((at, at + r.length, sizePt(r.style)))
            }
            if Set(spans.map { $0.size }).count > 1 {
                let starts = _lineStarts(painter, _map(i), count: u16.count)
                var table: [(from: Int, to: Int, big: Double)] = []
                for (k, st) in starts.enumerated() {
                    let en = k + 1 < starts.count ? starts[k + 1] : u16.count
                    let sizes = spans.filter { $0.from < en && $0.to > st }.map { $0.size }
                    if let big = sizes.max(), let lo = sizes.min(), big - lo > 0.01 { table.append((st, en, big)) }
                }
                if !table.isEmpty {
                    _topLift = table
                    _layoutParagraphBody(i, p, document)
                }
            }
        }
        defer { _topLift = nil }
        guard theme.wordRules, Self._honoursStopsPastMargin(document),
              !p.style.rightToLeft, p.style.alignment == .left || p.style.alignment == .justify,
              let painter = _painters[i] else { return }
        let single = painter.computeLineMetrics().count == 1
        guard let need = (single ? _pastNeed[i] : nil) ?? _pastLeft[i], need > 0.01 else { return }
        _pastWiden = max(need, _pastNeed[i] ?? 0, _pastLeft[i] ?? 0) + _px(80)
        _layoutParagraphBody(i, p, document)
        _pastWiden = nil
        if let again = _painters[i], again.computeLineMetrics().count != 1 {
            _layoutParagraphBody(i, p, document)
        } else {
            RuleTrace.hit("word-tab-past-the-margin-keeps-its-stop-on-one-line")
        }
    }

    func _layoutParagraphBody(_ i: Int, _ p: RichParagraph, _ document: RichDocument) {
        let f = _ParaFrame(self, i, p, document)
        f.go()
    }

    /// The width (points) of a paragraph that is a single `w:fitText` group, nil otherwise.
    @inline(never) static func _fitTextOverflow(_ p: RichParagraph) -> (groupPoints: Double, id: String)? {
        var found: (points: Double, id: String)? = nil
        for r in p.runs where r.length > 0 {
            guard let f = _fitText(r.style.keptXML), found == nil || found?.id == f.id else { return nil }
            found = f
        }
        guard let f = found else { return nil }
        return (f.points, f.id)
    }

    static func _picturesAndTabs(_ p: RichParagraph) -> Bool {
        // Opaque objects keep text-tab metrics: the legacy VML arrows
        // in zh-7773163d need that descent before the following boxes.
        !p.inlineImages.isEmpty && p.text.utf16.contains(0x09)
            && p.inlineImages.values.allSatisfy { !$0.data.isEmpty && $0.float == nil && $0.baseline == nil }
            && p.text.utf16.allSatisfy { $0 == 0xFFFC || $0 == 0x09 }
    }

    static func _textAlign(_ a: ParagraphAlignment) -> TextAlign {
        switch a {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .justify: return .justify
        }
    }
}

extension RichLayout {
    /// The style a first line stands on when it holds an unhinted em dash whose hAnsi face is East Asian over a Latin ascii face (ff493b's
    /// "Introduction \u{2014} ..." in Aptos Bold over a Malgun Gothic hAnsi): Word draws the dash in the hAnsi face, so the line takes that face's
    /// split ascent (Malgun Bold 1.088 em plus half the East Asian line's extra). The run's East Asian slot is set to the hAnsi family.
    static let _emDash: Character = "\u{2014}"
    @inline(never)
    func _eastDashLeadStyle(_ style: CharStyle, named: RichNamedStyle?) -> CharStyle? {
        guard let h = style.hAnsiFontFamily ?? named?.char.hAnsiFontFamily,
              theme.faceResolver?(h, false)?.isEastAsian == true else { return nil }
        if let latin = style.fontFamily ?? named?.char.fontFamily, latin == h, theme.faceResolver?(latin, false)?.isEastAsian == true { return nil }
        var out = style
        out.eastAsiaFontFamily = h
        RuleTrace.hit("word-em-dash-in-east-asian-hansi-face-stands-the-first-line-on-it")
        return out
    }

    /// The baseline rise of a first line that holds a Malgun-drawn symbol (①, ○, △, ·, ※, →, curly quotes) of a missing
    /// Korean face Word sets in Batang: the line's ascent is Malgun's 1.175 em against Batang's 1.009, times the spacing
    /// (c466d30a: the ① lines stood 3.4 pt high at 12 pt, 1.7 lines). The joiner of `_span` raises the line; the
    /// correction above had pulled the baseline back.
    @inline(never)
    /// Which lines of the paragraph hold a character Word draws in Malgun (the first-line rule's characters and faces).
    func _koreanSymbolLineFlags(_ p: RichParagraph, painter: TextPainter, lead: Int, named: RichNamedStyle?, document: RichDocument) -> [Bool] {
        let units = Array(p.text.utf16)
        var flags: [Bool] = []
        var from = 0
        while from < units.count {
            let end = max(from + 1, painter.getLineBoundary(TextPosition(offset: from + lead)).end - lead)
            var start = 0
            var found = false
            for run in p.runs where run.length > 0 {
                defer { start += run.length }
                let lo = max(start, from), hi = min(start + run.length, end, units.count)
                guard lo < hi, run.style.inlineImage == nil else { continue }
                let text = String(decoding: units[lo ..< hi], as: UTF16.self)
                let hit = text.unicodeScalars.contains { u in
                    let v = u.value
                    return v == 0x25CB || v == 0x25B3 || v == 0x25A1 || v == 0xB7 || (v >= 0x2460 && v <= 0x2469) || v == 0x203B || v == 0x2192
                        || v == 0x2018 || v == 0x2019 || v == 0x201C || v == 0x201D
                }
                guard hit else { continue }
                let viaEastAsia = theme.faceResolver?(run.style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                               ?? run.style.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.malgunSymbols == true
                let viaAscii = run.style.eastAsiaFontFamily == nil && run.style.fontFamily != nil
                    && theme.faceResolver?(run.style.fontFamily ?? "", true)?.malgunSymbols == true
                if !(run.style.eastAsiaFontFamily != nil && (run.style.fontHint ?? named?.char.fontHint) == "eastAsia"), viaEastAsia || viaAscii { found = true; break }
            }
            flags.append(found)
            from = end
        }
        return flags
    }

    func _koreanSymbolFirstLineRaise(_ p: RichParagraph, painter: TextPainter, lead: Int, named: RichNamedStyle?, document: RichDocument) -> Double? {
        let firstEnd = painter.getLineBoundary(TextPosition(offset: 0)).end - lead
        let units = Array(p.text.utf16)
        var start = 0
        var best: Double?
        for run in p.runs where run.length > 0 {
            defer { start += run.length }
            guard start < firstEnd else { break }
            let end = min(start + run.length, firstEnd, units.count)
            guard start < end, run.style.inlineImage == nil else { continue }
            let text = String(decoding: units[start ..< end], as: UTF16.self)
            let hit = text.unicodeScalars.contains { u in
                let v = u.value
                return (v >= 0x25A0 && v <= 0x25FF) || v == 0xB7 || (v >= 0x2460 && v <= 0x2469) || v == 0x203B || v == 0x2192
                    || v == 0x2018 || v == 0x2019 || v == 0x201C || v == 0x201D || v == 0xB1
            }
            let viaEastAsia = theme.faceResolver?(run.style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                                           ?? run.style.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily, true)?.malgunSymbols == true
            // (A quote or plus-minus sign that is a run of its own, set in Gulim, is drawn in Malgun Gothic: see `_span`'s joiner. xd b6f6c7d4 page 28.)
            let viaLone = run.style.loneQuote && !run.style.hAnsiNamedAsAscii
                && ["굴림", "gulim"].contains((run.style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? run.style.fontFamily ?? "").trimmingWhitespace().lowercased())
                && ["맑은 고딕", "malgun gothic"].contains((_normalChar(document)?.hAnsiFontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased())
            // (A run that names only a missing ascii face, with no eastAsia slot of its own, is judged by that face as in `_span`'s
            // joiner, though the style's eastAsia face is Batang itself: fe41a48c's 한양신명조 △△△ in 바탕글.)
            let viaAscii = run.style.eastAsiaFontFamily == nil && run.style.fontFamily != nil
                && (theme.faceResolver?(run.style.fontFamily ?? "", true)?.malgunSymbols == true || (run.style.fontFamily?.trimmingWhitespace() == "굴림" && text.unicodeScalars.contains { $0.value >= 0x25A0 && $0.value <= 0x25FF }))
            // (The won sign of a Korean Latin face with no ₩ of its own is Malgun's too: see `_span`'s joiner.)
            let won = text.unicodeScalars.contains { $0.value == 0x20A9 } && run.style.fontHint != "eastAsia"
                && theme.faceResolver?(run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false)?.isEastAsian == true
            guard (hit || won), !(run.style.eastAsiaFontFamily != nil && (run.style.fontHint ?? named?.char.fontHint) == "eastAsia"),
                  viaEastAsia || viaAscii || viaLone || won else { continue }
            let size = run.style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
            // (Word's shift is a constant 0.2833 em once the spacing is over single:
            // the same 3.4pt at 12pt for 1.7x (lab c466d30a) and 3x (xd 07eecf7a);
            // at single it stays 0.166 em.)
            // (Malgun's 1.288 em box above the baseline less the paragraph face's 1.006 em at the line's largest size: the same 0.2833 em
            // when the symbol is the largest run; a 11 pt quote beside 12 pt text rises only 2.1 pt, as Word's b6f6c7d4 page 5.)
            var tallest = size
            do {
                var s2 = 0
                for r2 in p.runs where r2.length > 0 {
                    defer { s2 += r2.length }
                    guard s2 < firstEnd else { break }
                    tallest = max(tallest, r2.style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize)
                }
            }
            let rise = 1.288 * size - 1.006 * tallest
            if rise > (best ?? 0) {
                RuleTrace.hit("word-korean-symbol-first-line-stands-on-malgun-ascent")
                best = rise
            }
        }
        return best
    }
}

extension RichLayout {
    /// Does a Shonar Bangla first line hold a Latin-drawn character? Letters and digits are Latin. A neutral ASCII mark (punctuation, space, underscore) takes the
    /// script of the strong characters in its OWN run: inside a run with Bengali it is drawn in Shonar (a comma in 3f7da49c's bullets), and a run of neutrals alone
    /// uses its ascii face (": ____" in an Arial run, 80152175). The rule is Word's; it replaced a code-point cutoff.
    @inline(never)
    func _shonarFirstLineHasLatin(_ p: RichParagraph, units: [UInt16], firstEnd: Int, named: RichNamedStyle?, document: RichDocument) -> Bool {
        var start = 0
        for run in p.runs where run.length > 0 {
            defer { start += run.length }
            guard start < firstEnd else { break }
            let end = min(start + run.length, firstEnd, units.count)
            guard start < end, run.style.inlineImage == nil else { continue }
            let slice = units[start ..< end]
            if slice.contains(where: { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) }) { return true }
            // (A space between Bengali words takes their script whatever its run's face: 80152175's Arial space run does not lift line 1.)
            guard slice.contains(where: { $0 > 0x20 && $0 <= 0x7E }) else { continue }
            if String(decoding: slice, as: UTF16.self).unicodeScalars.contains(where: { Self._indic.contains($0.value) }) { continue }
            let face = (run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
            if Self._bengaliMissingFace(face, document) != "shonar bangla" { return true }
        }
        return false
    }
}

extension RichLayout {
    /// The baseline a first line of Indic letters stands at when its face's ascent is above `target`.
        /// A first line with a character Word draws in Mangal for Noto Sans Tamil text (see `_markInMangal`, `_latinInNotoTamil`).
    @inline(never)
    func _firstLineHoldsMangalMark(_ p: RichParagraph, painter: TextPainter, lead: Int, named: RichNamedStyle?, document: RichDocument) -> Bool {
        let firstEnd = painter.getLineBoundary(TextPosition(offset: 0)).end - lead
        let units = Array(p.text.utf16)
        var start = 0
        for run in p.runs where run.length > 0 {
            defer { start += run.length }
            guard start < firstEnd else { break }
            let end = min(start + run.length, firstEnd, units.count)
            guard start < end, run.style.inlineImage == nil else { continue }
            let text = String(decoding: units[start ..< end], as: UTF16.self)
            let isMark: (Unicode.Scalar) -> Bool = { !Self._isIndic($0.value) && $0.value > 0x20 && $0.value != 0xA0 && $0.value != 0x200B && $0.value != 0x200C && $0.value != 0x200D && $0.value != 0x2060 && $0.value != 0xFFFC }
            guard text.unicodeScalars.contains(where: isMark) else { continue }
            if Self._latinInNotoTamil(run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? ""),
               !text.unicodeScalars.contains(where: { Self._isIndic($0.value) }) { return true }
            if Self._markInMangal(run.style.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "", p.text[...]) { return true }
        }
        return false
    }

    @inline(never)
    func _indicFirstLineAscent(_ p: RichParagraph, painter: TextPainter, lead: Int, named: RichNamedStyle?, document: RichDocument, target: Double,
                                style: RichParagraphStyle, pitch: Double?, lift: inout Double) -> Double? {
        var target = target
        var raisedTo: Double?
        var latinFloor = 0.0
        var markerFloor = false
        var kokilaOwn = 0.0
        var kokilaLine = 0.0
                    let firstEnd = painter.getLineBoundary(TextPosition(offset: 0)).end - lead
                    let units = Array(p.text.utf16)
                    var start = 0
                    // (A list's marker in a Latin face of its own (Symbol, a bullet) stands the first line on that face's ascent as a Latin run does:
                    // xd d760f1e5's "•" headings, Symbol 14 pt bold in a Kokila paragraph at 1.5 lines, 3.8 pt lower in Word's print.)
                    if p.style.list != nil, let face = _levelNumberFonts(p, document).latin?.trimmingWhitespace().lowercased(), face != "kokila",
                       var marker = p.runs.first(where: { $0.length > 0 })?.style {
                        marker.fontFamily = _levelNumberFonts(p, document).latin
                        if let size = _levelNumberSize(p, document) { marker.fontSize = size }
                        if let b = theme.baseline(for: marker, in: style, named: named, eastAsian: false, gridPitch: pitch, centresInLine: document.spacesForUnderline) {
                            RuleTrace.hit("word-list-marker-face-raises-the-first-line")
                            latinFloor = max(latinFloor, b); markerFloor = true
                        }
                    }
                    for run in p.runs where run.length > 0 {
                        defer { start += run.length }
                        guard start < firstEnd else { break }
                        let end = min(start + run.length, firstEnd, units.count)
                        guard start < end, run.style.inlineImage == nil else { continue }
                        let text = String(decoding: units[start ..< end], as: UTF16.self)
                        guard text.unicodeScalars.contains(where: { Self._isIndic($0.value) || ($0.value >= 0x0D00 && $0.value <= 0x0DFF) }) else {
                            // (A Latin run of Arial Unicode MS with no w:cs flag in a Devanagari paragraph is drawn in Yu Gothic, which stands the first line on its own
                            // 1.18 em ascent: lab aumsy2, Word's step into such a line 12.8 pt against 12.0 for a Nirmala one; fb94294e.)
                            if document.readFromFile, document.fontCharsets["arial unicode ms"] == "80",
                               text.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x7F }),
                               (run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms",
                               !(run.style.keptXML?.containsSubstring("<w:cs/>") ?? false), !(run.style.keptXML?.containsSubstring("<w:cs ") ?? false),
                               p.text.unicodeScalars.contains(where: { $0.value >= 0x900 && $0.value < 0xB00 }) {
                                let size = run.style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                                if size * Self._yuGothicLine.0 > target + 0.01 {
                                    RuleTrace.hit("word-yu-gothic-latin-run-stands-the-first-line-on-its-ascent")
                                    target = size * Self._yuGothicLine.0
                                    raisedTo = target
                                }
                            }
                            // (A Latin run of a Tamil-language document, a complex-script (w:cs) run of Arial Unicode MS, in a paragraph with no Tamil letter: its line is
                            // Nirmala UI's, standing on 1.079 em; dx2 a347c3b3's "00 month 20XX", 1.64 pt lower in Word's print than the Latin stand-in's.)
                            if document.defaultLangXML?.containsSubstring("ta-IN") == true,
                               run.style.keptXML.map({ $0.containsSubstring("<w:cs/>") || $0.containsSubstring("<w:cs ") }) == true,
                               (run.style.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased() == "arial unicode ms",
                               !p.text.unicodeScalars.contains(where: { Self._tamil.contains($0.value) }),
                               let nirmala = Self._indicLines["nirmala ui"] {
                                let size = run.style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                                if size * nirmala.0 > target + 0.01 {
                                    RuleTrace.hit("word-tamil-doc-latin-cs-run-stands-the-first-line-on-nirmalas-ascent")
                                    target = size * nirmala.0
                                    raisedTo = target
                                }
                            }
                            // (A run of Latin letters on a Kokila line stands the line on its own face's baseline where that is the taller: dx2 cbb7ae39's
                            // "IRB" and "SS", Times New Roman 10 pt beside 10 pt Kokila, lab cb7: 9.3 pt above the baseline in Word's print, Kokila's 7.3.)
                            if text.unicodeScalars.contains(where: { ($0.value | 0x20) >= 0x61 && ($0.value | 0x20) <= 0x7A }),
                               (run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() != "kokila",
                               let b = theme.baseline(for: run.style, in: style, named: named, eastAsian: false, gridPitch: pitch, centresInLine: document.spacesForUnderline) { latinFloor = max(latinFloor, b) }
                            continue
                        }
                        var cs = (run.style.complexFontFamily ?? named?.char.complexFontFamily ?? _normalChar(document)?.complexFontFamily ?? "").trimmingWhitespace().lowercased()
                        switch cs {
                        case "kalimati": cs = "mangal"
                        case "mangal", "kokila", "aparajita", "raavi", "shruti", "gautami", "vrinda", "utsaah", "shonar bangla": break
                        default: cs = text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value < 0xA00 }) ? Self._bengaliMissingFace(cs, document) : "nirmala ui"
                        }
                        // (Shonar Bangla Bold is its own face: 1721+978 of 2048; a first line of Bengali alone stands on its ascent, 15.1 pt at 18 pt, not on the stand-in's 0.96 em: dx2 3f7da49c's title, Word's baseline 60.1.)
                        let shonarBold = cs == "shonar bangla" && (run.style.bold || ((named?.char.bold ?? false) && !run.style.off.contains(.bold)))
                        guard let metrics = Self._indicLines[shonarBold ? "shonar bangla bold" : cs] else { continue }
                        let size = run.style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                        // (Utsaah with Utsaah as its Latin face too: the first line stands on Utsaah's 0.741 em, LOWER than the Latin
                        // stand-in's 0.95; lab utsaah1, Word's baseline 11.9 pt under the margin at 16 pt, ours 15.4.)
                        // (A Kokila line with no Latin letter on it stands on Kokila's ascent whatever the paragraph's Latin face: dx2 cbb7ae39's
                        // header and heading, Calibri as the Latin face, 10 and 12 pt Hindi alone on the line, 2 pt higher in Word's print.)
                        let noLatin = (cs == "kokila" || cs == "shonar bangla") && !(cs == "shonar bangla"
                            ? _shonarFirstLineHasLatin(p, units: units, firstEnd: firstEnd, named: named, document: document)
                            : units[0 ..< min(firstEnd, units.count)].contains(where: { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) }))
                        if cs == "utsaah" || cs == "kokila" || (cs == "shonar bangla" && noLatin), noLatin || (run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased() == cs,
                           abs(size * metrics.0 - target) > 0.01,
                           // (An at-least line taller than the face keeps its old place: 6c7504e9 heading, 24 pt at least over a 16 pt face. A multiple puts its extra under the line, so the baseline stays on the face's ascent: lab mmatrix2.)
                           !(cs == "kokila" && ((p.style.lineHeightPoints ?? 0) > size * (metrics.0 + metrics.1) + 0.01)) {
                            RuleTrace.hit("word-utsaah-first-line-stands-on-utsaah-ascent")
                            target = size * metrics.0
                            raisedTo = target
                            kokilaOwn = target
                            kokilaLine = size * (metrics.0 + metrics.1)
                        } else if size * metrics.0 > target + 0.01, !(cs == "nirmala ui" && (style.lineHeightPoints == nil || style.lineHeightIsMinimum)
                                  && _isSolaimanLipi(run.style, named, document)
                                  && units[0 ..< min(firstEnd, units.count)].contains(where: { $0 >= 0x20 && $0 < 0x7F })) {
                            RuleTrace.hit("word-indic-first-line-stands-on-its-face-ascent")
                            // (Under a multiple below single the ascent is cut in proportion: Word's 14 pt bold Nirmala heading at 0.9 stands 13.70 pt under the margin, 1.079 x 14 x 0.9 = 13.60, not the 15.11 of the whole ascent. lab pa-bullet.)
                            let cut = cs == "nirmala ui" && p.style.lineHeightPoints == nil && p.style.lineSpacing > 0.5 && p.style.lineSpacing < 1 ? p.style.lineSpacing : 1
                            if cut != 1 { RuleTrace.hit("word-nirmala-first-line-under-a-multiple-below-single-cuts-the-ascent-in-proportion") }
                            target = size * metrics.0 * cut
                            raisedTo = target
                        } else if cs == "nirmala ui", style.lineHeightPoints == nil || style.lineHeightIsMinimum, let mangal = Self._indicLines["mangal"],
                                  _isSolaimanLipi(run.style, named, document),
                                  units[0 ..< min(firstEnd, units.count)].contains(where: { $0 >= 0x20 && $0 < 0x7F }) {
                            // (A first line holding a space or ASCII mark in a missing Bengali face (SolaimanLipi) is Mangal's own line, Word draws those in Mangal:
                            // the baseline stands on Mangal's ascent, 14.9 pt at 12 pt, not on the Latin face's; under an "at least" height the extra goes above
                            // the baseline only where Mangal's falls short of the minimum. xd 73caaeda's authors line, 13.5 pt at least 22.5: Word's step into it
                            // 21.4, ours 23.5; its body's first line 20.8 under the rule of dashes, ours 18.9.)
                            let stand = style.lineHeightPoints.map { max(size * mangal.0, $0 - size * mangal.1) } ?? size * mangal.0
                            if abs(stand - target) > 0.01 {
                                RuleTrace.hit("word-solaimanlipi-first-line-stands-on-mangal-ascent")
                                target = stand
                                raisedTo = target
                            }
                        } else if cs == "nirmala ui", size * metrics.0 < target - 0.01, _nikoshLettersOnlyLine(units, firstEnd, run, named, document) {
                            // (A line of Bengali letters and spaces in Nikosh, a face Windows lacks: Word draws the letters in Nirmala UI
                            // and stands the line on Nirmala's ascent, 1.079 em, not on Mangal's 1.241 that the paragraph's Latin face
                            // gives the strut. dx2 bede0fbc's header lines and its "রিটার্ন রেজিস্টারের" rows: 2 pt (12 pt text) and
                            // 1.6 pt (11 pt) higher in Word's print, a line with a bracket (Mangal) where ours was right.)
                            RuleTrace.hit("word-nikosh-letters-line-stands-on-nirmala-ascent")
                            target = size * metrics.0
                            raisedTo = target
                        }
                    }
                    if kokilaOwn > 0, latinFloor > kokilaOwn + 0.01 {
                        // (Less what the engine's own first line already stands above Kokila's ascent: a paragraph whose strut is not forced grows the line itself.)
                        let given = max(0, (painter.computeLineMetrics().first.map { $0.baseline / max(0.0001, _px(1)) } ?? kokilaOwn) - kokilaOwn)
                        // (A marker face of its own: the engine's own taller strut already grows the line by its multiple of the difference; only the rest is lifted.)
                        let engineGrowth = markerFloor ? max(0, painter.height / max(0.0001, _px(1)) - Double(max(1, painter.computeLineMetrics().count)) * kokilaLine * max(1, style.lineSpacing)) : given
                        let more = latinFloor - kokilaOwn - engineGrowth
                        if more > 0.01 { lift = max(lift, more) }
                        raisedTo = latinFloor
                    }
                        return raisedTo
    }
}


extension RichLayout {
    /// A top-and-bottom or square/tight-wrapped picture more than 2pt above the empty first paragraph of the document that holds it
    /// (dx2 en 61ec937a: a square-wrapped logo 40pt above stands at the margin, 72.0 in Word's print, and the text wraps beside it).
    @inline(never)
    func _atPageTopNegativeOffset(_ i: Int, _ image: ImageAttachment) -> Bool {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, let f = image.float, (f.bandsPage || (f.wraps && !f.wrapsTight && image.textBox == nil && image.sourceXML?.containsSubstring("txbxContent") != true)), f.verticalAlign == nil,
              f.verticalFrom == "paragraph", f.y < -2, i == 0, !floatsFrames, regionTopOnPage == nil else { return false }
        // (One lying wholly above its paragraph is not lifted: sa1 8e800da4's 28pt picture 50.4pt up stands 57.6pt from its paragraph's top in Word's print, ours at the paragraph's.)
        if f.y + image.height + f.effectBottom <= 0 { return false }
        return true
    }
}

extension RichLayout {
    /// The first line holds only Indic letters, spaces and joiners, and the run's Latin face is Nikosh.
    @inline(never)
    func _nikoshLettersOnlyLine(_ units: [UInt16], _ firstEnd: Int, _ run: Run, _ named: RichNamedStyle?, _ document: RichDocument) -> Bool {
        let latin = (run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? "").trimmingWhitespace().lowercased()
        // (Siyam Rupali, Windows lacks it too and Word draws its Bengali letters in Nirmala UI: lab e86-pitch, every Bengali-only page's first
        // baseline 2.1 pt higher in Word's print than ours, which stood it on Malgun Gothic's ascent, the face its Latin falls to.)
        guard latin == "nikosh" || latin == "siyam rupali" else { return false }
        for u in units[0 ..< min(firstEnd, units.count)] {
            if u == 0x20 || u == 0x200B || u == 0x200C || u == 0x200D || u == 0x2060 || u == 0xA0 { continue }
            if Self._isIndic(UInt32(u)), u != 0x964, u != 0x965 { continue }
            return false
        }
        return true
    }
    /// For each line of `painter`, whether the word that starts it is no wider than `room`: the test for a left piece beside a box (a
    /// word of ideographs is one character).
    @inline(never)
    static func _nextWordFits(_ painter: TextPainter, _ span: InlineSpan, room: Double) -> [Bool] {
        let units = Array(span.toPlainText(includeSemanticsLabels: false, includePlaceholders: true).utf16)
        var out: [Bool] = []
        var at = 0
        while at < units.count {
            let r = painter.getLineBoundary(TextPosition(offset: at))
            let s = max(r.start, at)
            var e = s
            if e < units.count, units[e] >= 0x2E80 { e += 1 } else {
                while e < units.count, units[e] != 0x20, units[e] != 0x0A, units[e] != 0x200B, units[e] != 0x2D, !(units[e] >= 0x2E80) { e += 1 }
                if e < units.count, units[e] == 0x2D { e += 1 }
            }
            var w = 0.0
            if e > s { for b in painter.getBoxesForSelection(TextSelection(baseOffset: s, extentOffset: e)) { w += b.right - b.left } }
            out.append(w <= room + 0.01)
            guard r.end > at || r.end > r.start else { break }
            at = max(r.end, at + 1)
        }
        return out
    }

}

extension RichLayout {
    /// The unscaled first-line baseline of the text and the excess of a list number's face over it (points), for a number in a taller face at its own size.
    func _labelFaceGrowth(_ p: RichParagraph, named: RichNamedStyle?, document: RichDocument, style: RichParagraphStyle) -> (target: Double, growth: Double)? {
        guard !p.runs.isEmpty, let firstRun = p.runs.first(where: { $0.length > 0 }),
              let xml = p.style.listId.flatMap({ document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.numberRPrXML }),
              let r = xml.rangeOfSubstring("w:ascii=\"") else { return nil }
        let family = String(xml[r.upperBound...].prefix { $0 != "\"" })
        let textFace = firstRun.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily
        let size = firstRun.style.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
        let numberSize = _levelNumberSize(p, document) ?? size
        guard !family.isEmpty, numberSize <= size + 0.01,
              let nb = theme.faceResolver?(family, false)?.baseline, let tb = theme.faceResolver?(textFace, false)?.baseline,
              nb * numberSize - tb * size > 0.02,
              let target = theme.baseline(for: firstRun.style, in: style, named: named, eastAsian: false, gridPitch: nil, centresInLine: document.spacesForUnderline) else { return nil }
        return (target, nb * numberSize - tb * size)
    }
}
