// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Lines": moved out of RichLayout.swift by test/tools/split-richlayout.py (a pure move, so that
// the parts compile side by side).

import Flutter
import FlutterSwiftBridge
import Foundation

extension RichLayout {

    func _strut(_ span: TextSpan, tallest: Bool = false, near nearCounts: Bool = false, wide: Bool = false, joiners: Bool = true) -> StrutStyle? {
        guard theme.wordRules else { return nil }
        var first: TextStyle? = nil
        var uniform = true
        var count = 0
        // (Text shifted off the baseline counts only where nothing else
        // does: a paragraph raised whole by `w:position`, zh-10e3a42be's
        // clauses 10.5pt up in 30pt exact lines, is held to its height
        // like any other, where the engine's own line — the run's ascent
        // and descent moved with it — had set the text lower, not higher.)
        var shiftedToo = false
        // (Nor does white space, where there is anything else: its face
        // and size set no line in Word. Lab `el` (Word for Windows,
        // zh-2f9463d6's package, 12pt Times beside 微软雅黑): "AB　",
        // "A　B", "　AB" and "AB" with a 20pt space, U+3000 or ASCII, are
        // the lines "AB" is, on a line grid and off it; "AB测" is YaHei's.
        // zh-2f9463d6's "……　" cells stood a pitch tall.)
        var blanksToo = false
        // (Nor a bold run beside its regular face at the same size, whose
        // line is a hair taller: zh-86547e97's "第一条" (Strong, YaHei bold
        // for 仿宋_GB2312, 16pt at 1.5 lines) opens a paragraph whose lines
        // stand 41.0-41.3pt apart in Word's print, the first with them —
        // regular YaHei's 41.16, not bold's 41.5. Without a strut the
        // engine stacked the two faces' boxes and the line was 54. Such a
        // line is held at the height most of its text has.)
        var share: [Double: (TextStyle, Int, Int)] = [:]
        var near = false
        // (Nor marks beside Arabic or Hebrew letters, the second time round: a
        // non-breaking hyphen or a middle dot set in the Latin theme face
        // (Aptos) among Arial's Arabic held a strut back, and the line ran
        // on the fallback's height, 18.4pt to Word's 16.0 in fas-z22973278.)
        var marksToo = false
        var bidi = false
        // (A run moved off the baseline whose line is taller than the held one: a ruby's base on a line
        // grid, which asks its line for two pitches. A strut would hold the line at one: flt1-1-asis's
        // wrapped "かえてくれる" paragraph came out 18 pt short.)
        var tallShifted = 0.0
        var kokilaOwn = false, latinOwn = false, latinStacked = false, bengaliSeen = false, nirmalaSeen = false
        func visit(_ s: InlineSpan) {
            guard uniform, let t = s as? TextSpan else { return }
            if let st = t.style, let tx = t.text, tx.unicodeScalars.contains(where: { $0.value >= 0x900 && $0.value < 0xD80 }), st.ascentOverride != nil, st.debugLabel?.lowercased().containsSubstring("nirmala ui") == true { nirmalaSeen = true }
            if let st = t.style, let tx = t.text {
                if st.ascentOverride != nil, st.debugLabel?.lowercased().containsSubstring("kokila") == true { kokilaOwn = true }
                else if st.ascentOverride == nil, tx.unicodeScalars.contains(where: { $0.value > 0x20 && $0.value < 0x250 }), !tx.unicodeScalars.contains(where: { $0.value >= 0x900 && $0.value < 0xD80 }) { latinOwn = true }
                // (A Latin run that carries its own ascent and descent (beside Shonar Bangla, lab stk1) stacks on the Indic joiner per line: the strut is a minimum, not the height.)
                else if st.ascentOverride != nil, tx.unicodeScalars.contains(where: { $0.value >= 0x20 && $0.value < 0x250 && ($0.properties.isAlphabetic || ($0.value >= 0x30 && $0.value <= 0x39)) }), !tx.unicodeScalars.contains(where: { $0.value >= 0x900 && $0.value < 0xD80 }) { latinStacked = true }
            }
            if let text = t.text, text.unicodeScalars.contains(where: { $0.value >= 0x980 && $0.value < 0xA00 }) { bengaliSeen = true }
            if !shiftedToo, let st = t.style, st.baselineShift != nil, let sz = st.fontSize, let hh = st.height, sz > 0.5 { tallShifted = max(tallShifted, sz * hh) }
            if let text = t.text, text.unicodeScalars.contains(where: { ($0.value >= 0x0590 && $0.value <= 0x08FF) || ($0.value >= 0xFB1D && $0.value <= 0xFEFF) }) { bidi = true }
            if let text = t.text, marksToo, !text.contains(where: { $0.isLetter || $0.isNumber }) {
                for c in t.children ?? [] { visit(c) }
                return
            }
            if let text = t.text, blanksToo || text.contains(where: { !Self._setsNoLine($0) }),
               joiners || text.contains(where: { $0 != "\u{2060}" }),
               let style = t.style, style.baselineShift == nil || shiftedToo, let size = style.fontSize, let h = style.height, h > 0.05, size > 0.5 {
                count += 1
                let met = share.count
                share[size * h, default: (style, 0, met)].1 += text.count
                if let f = first, let fs = f.fontSize, let fh = f.height {
                    if tallest {
                        if size * h > fs * fh + 0.01 { first = style }
                    } else if abs(fs * fh - size * h) > 0.01 {
                        if nearCounts && Self._sameLine(size, h, fs, fh, wide: wide) { near = true } else { uniform = false }
                    }
                } else {
                    first = style
                }
            }
            for c in t.children ?? [] { visit(c) }
        }
        visit(span)
        if !uniform, bidi, theme.wordRules, RichTextTheme.wordWindowsPages {
            // Only a paragraph that has Arabic or Hebrew in it, and only where it had no strut.
            marksToo = true; uniform = true; first = nil; count = 0; share = [:]; near = false
            visit(span)
            // (Held to a face named Arial only: fas-z15800253's B Zar, a face Word has not got, is 1.22 em
            // in its print — the Latin theme face's — and Arial's 1.15 made it 17.4 for 18.4. The name is the
            // authored one, debugLabel; the family is the stand-in's, Arial for B Zar too.)
            if first?.debugLabel?.trimmingWhitespace().lowercased() != "arial" { uniform = false }
        }
        if count == 0, uniform { blanksToo = true; visit(span) }
        if count == 0, uniform { shiftedToo = true; visit(span) }
        // (The tallest stretch too, where others are within a hair of it:
        // the one most of the text has. zh-86547e97's paragraph also holds
        // a 15pt run, so it is held by its tallest, and that was the bold
        // "第一条" on its first line alone — no strut, and the line 13pt
        // low.)
        var held = first
        if let top = first, let ts = top.fontSize, let th = top.height, near || (tallest && nearCounts) {
            let alike = share.filter { Self._sameLine($0.value.0.fontSize ?? 0, $0.key / max(0.01, $0.value.0.fontSize ?? 1), ts, th, wide: wide) }
            // (A tie in text goes to the stretch met first: the dictionary's
            // own order is not the same from one run to the next.)
            if alike.count > 1 { held = alike.values.max { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 > $1.2 }?.0 ?? top }
        }
        guard uniform, count > 0, let base = held, let size = base.fontSize, let h = base.height else { return nil }
        if !shiftedToo, tallShifted >= size * h * 1.6 { return nil }
        // (A run that carries its own ascent and descent (Kokila's, split at a line multiple by `_multipleSplit`) sets its line itself: a strut in the
        // stand-in's face put the baseline 4.1 pt low at 18 pt on every line above single. lab mmatrix2.)
        if base.ascentOverride != nil, base.debugLabel?.lowercased().containsSubstring("kokila") == true { return nil }
        if latinStacked && bengaliSeen { return nil }
        if wide, base.ascentOverride != nil, Self._thaiLineSplit(base.debugLabel, bold: false) != nil { return nil }
        // (Even leading: the engine's proportional strut scales the
        // face's ascent and descent by a height that counts its line gap
        // too, and comes out that much short — 15.15 for 15.6 in
        // Liberation Sans.)
        return StrutStyle(fontFamily: base.fontFamily, fontFamilyFallback: base.fontFamilyFallback,
                          fontSize: size, height: h, leadingDistribution: .even, fontWeight: base.fontWeight,
                          forceStrutHeight: !((kokilaOwn && latinOwn) || (latinStacked && bengaliSeen)
                                              // (A Nirmala UI line is its tallest ascent over its deepest descent, so a deeper Latin face (Calibri's 0.269 against 0.247 em) lengthens the lines it is on: lab nirpitch2, 14.88 against 14.64 at 11 pt.)
                                              || (theme.wordRules && RichTextTheme.wordWindowsPages && nirmalaSeen)))
    }

    /// The span with the Latin stretches that share a line with ideographs set no taller than the
    /// ideographs' own line, or nil where none needs it. A Latin stretch drawn by a stand-in face (a digit
    /// or a space among 標楷體's ideographs) splits its height above and below the baseline its own way, and
    /// the line it shares stacks taller than either: zh-15f60bac's 16pt lines with a space in them stood
    /// 22.2pt apart, 20.8 in Word's print, where the face is one. A paragraph with a strut is held to it;
    /// this is for the one that has none (its sizes differ) — each such stretch keeps its width and loses
    /// its height where a taller-or-equal ideograph stretch is on the same line.
    static func _unstackedFaces(_ span: TextSpan, _ painter: TextPainter) -> TextSpan? {
        struct Leaf { var range: Range<Int>; var size: Double; var box: Double; var family: String?; var ascii: Bool; var ideo: Bool }
        var leaves: [Leaf] = []
        var at = 0
        var simple = true
        func visit(_ s: InlineSpan) {
            guard let t = s as? TextSpan else {
                if s is PlaceholderSpan { at += 1 } else { simple = false }
                return
            }
            if let text = t.text {
                let n = text.utf16.count
                if let st = t.style, let fs = st.fontSize, let h = st.height, n > 0 {
                    let blank = text.unicodeScalars.allSatisfy { $0.properties.isWhitespace }
                    leaves.append(Leaf(range: at ..< at + n, size: fs, box: fs * h, family: st.fontFamily,
                                       ascii: st.debugLabel != "yu-joiner" && text.utf16.allSatisfy { $0 < 0x2E80 }, ideo: !blank && text.utf16.contains { $0 >= 0x2E80 }))
                } else { simple = false }
                at += n
            }
            for c in t.children ?? [] { visit(c) }
        }
        visit(span)
        guard simple, leaves.count > 1 else { return nil }
        let metrics = painter.computeLineMetrics()
        guard metrics.count >= 1 else { return nil }
        func lines(_ r: Range<Int>) -> Set<Int> {
            var out = Set<Int>()
            for box in painter.getBoxesForSelection(TextSelection(baseOffset: r.lowerBound, extentOffset: r.upperBound)) {
                let middle = (box.top + box.bottom) / 2
                if let k = metrics.firstIndex(where: { middle >= $0.baseline - $0.ascent && middle <= $0.baseline + $0.descent }) { out.insert(k) }
            }
            return out
        }
        var reference = [Leaf?](repeating: nil, count: metrics.count)
        var leafLines: [Set<Int>] = []
        for leaf in leaves {
            let ls = lines(leaf.range)
            leafLines.append(ls)
            guard leaf.ideo else { continue }
            for k in ls where reference[k].map({ leaf.box > $0.box }) ?? true { reference[k] = leaf }
        }
        var marked = Set<Int>()
        for (i, leaf) in leaves.enumerated() where leaf.ascii && !leafLines[i].isEmpty {
            let refs = leafLines[i].map { reference[$0] }
            guard refs.allSatisfy({ $0 != nil }) else { continue }
            guard refs.allSatisfy({ r in leaf.box <= r!.box + 0.01 }) else { continue }
            marked.insert(i)
        }
        guard !marked.isEmpty else { return nil }
        var index = 0
        func rebuild(_ s: InlineSpan) -> InlineSpan {
            guard let t = s as? TextSpan else { return s }
            var style = t.style
            if t.text != nil {
                if marked.contains(index) { style = style?.copyWith(height: 0.01) }
                index += 1
            }
            return TextSpan(text: t.text, children: t.children?.map { rebuild($0) }, style: style, recognizer: t.recognizer, locale: t.locale)
        }
        return rebuild(span) as? TextSpan
    }

    /// Whether each of `painter`'s lines holds some text of the span's
    /// tallest stretch (the height `strut` was made from).
    static func _tallestOnEveryLine(_ span: TextSpan, _ strut: StrutStyle, _ painter: TextPainter, lines: Int, near: Bool = false, wide: Bool = false) -> Bool {
        guard let size = strut.fontSize, let h = strut.height else { return false }
        var ranges: [Range<Int>] = []
        var at = 0
        func visit(_ s: InlineSpan) {
            guard let t = s as? TextSpan else { at += 1; return }
            if let text = t.text {
                let n = text.utf16.count
                if let style = t.style, let fs = style.fontSize, let fh = style.height, near ? Self._sameLine(fs, fh, size, h, wide: wide) : abs(fs * fh - size * h) < 0.01,
                   text.unicodeScalars.contains(where: { !$0.properties.isWhitespace }) {
                    ranges.append(at ..< at + n)
                }
                at += n
            }
            for c in t.children ?? [] { visit(c) }
        }
        visit(span)
        let metrics = painter.computeLineMetrics()
        var held = Set<Int>()
        for r in ranges {
            for box in painter.getBoxesForSelection(TextSelection(baseOffset: r.lowerBound, extentOffset: r.upperBound)) {
                let middle = (box.top + box.bottom) / 2
                if let k = metrics.firstIndex(where: { middle >= $0.baseline - $0.ascent && middle <= $0.baseline + $0.descent }) {
                    held.insert(k)
                }
            }
        }
        // (An empty line — a break after a break — holds no text to find,
        // and is held where its own height is the stretch's already: the
        // break's run is that stretch's. zh-0978dee9's cells of 仿宋 with
        // "\n\n" between items lost their strut to their empty lines, and
        // every line with a digit, Liberation Mono for 仿宋's own half-width
        // Latin, stood 13.86pt for Word's 12.96.)
        for (k, m) in metrics.enumerated() where !held.contains(k) && m.width < 0.5 && abs(m.height - size * h) < max(0.5, size * h * 0.01) {
            held.insert(k)
        }
        return held.count == lines
    }

    /// The first line's indent in points, where the theme sets first
    /// lines in: positive in, negative out (hanging). Word's
    /// `w:firstLineChars` and `w:hangingChars` count characters of the
    /// paragraph's first run and outrank the measure beside them. A
    /// list's marker has its own slot, and an empty paragraph no line
    /// to indent.
    public func firstLineIndent(_ p: RichParagraph, at index: Int? = nil, _ document: RichDocument) -> Double {
        // PowerPoint's unbulleted paragraph starts its first line where its
        // own indent puts it — out to the left of the rest for a negative
        // one, as a master's body hangs every level (ecodesign's quotes) —
        // where this returned nothing outside Word.
        if !theme.wordRules {
            guard p.style.list == nil, !p.text.isEmpty, p.image == nil, p.cell == nil else { return 0 }
            return p.style.firstLineIndent
        }
        // (Nor the rest of a paragraph a page break split: zh-694447ca's
        // title runs on past a break from "（此件公开发布）" under
        // firstLineChars 200, and Word's print has it at the margin on the
        // next page, where ours set it 39pt in and wrapped its "装修、".)
        guard p.style.list == nil, !p.text.isEmpty, p.image == nil, !p.style.continuesParagraph else { return 0 }
        let chars = Double(p.style.eastAsian["w:hangingChars"] ?? "").map { -$0 } ?? Double(p.style.eastAsian["w:firstLineChars"] ?? "")
        if let chars, chars != 0 {
            // (A character of the first run: its size, and its character
            // spacing with it.)
            // (Not a run that only anchors a drawing: zh-5d635acc's footer
            // line opens with one, and Word counts its 2000 characters
            // at the "X" after it, 16pt — w:firstLine 6400 — where ours
            // took the style's 9pt and the line held "X 济".)
            let named = _named(p, document)
            let first = _firstTextRun(p)
            // (A paragraph that opens with a drawing's anchor, whose run
            // is none of the text's: Word's own twips are what its print
            // follows. zh-e49d7943's "（二）" paragraph, the anchor at the
            // Normal 12pt and the text at 17: hangingChars 300 and hanging
            // 720, text at 54 and the first line at 18 in the print, not
            // the 3 x 17 the text's size gives.)
            if let anchor = p.runs.first, anchor.length > 0, p.text.utf16.prefix(anchor.length).allSatisfy({ $0 == 0xFFFC }),
               p.style.firstLineIndent != 0, (chars < 0) == (p.style.firstLineIndent < 0),
               RichTextTheme.wordWindowsPages, p.style.eastAsian["w:indentStored"] == "1" {
                RuleTrace.hit("word-chars-indent-after-drawing-anchor-follows-twips")
                return p.style.firstLineIndent - _topLineSqueeze(p, document)
            }
            // (The paragraph's own style's size where it has one: zh-b24b396a's footer page number,
            // style 9pt under Normal's 12, firstLineChars 200 from Normal, is 18pt in, not 24, in
            // Word's print; zh-c2c92639's TOC entries take Normal's as their style sets none.)
            let fieldFirst = RichTextTheme.wordWindowsPages && p.style.eastAsian["w:fieldFirst"] == "1"
            let size: Double = fieldFirst ? (named?.char.fontSize ?? document.styles[RichNamedStyle.normalId]?.char.fontSize ?? theme.fontSize) : (first?.style.fontSize ?? named?.char.fontSize ?? theme.fontSize)
            var spacing: Double = first?.style.letterSpacing ?? named?.char.letterSpacing ?? 0
            // (Twice where the document balances its widths: see `_span`.)
            if document.balancesSpaceWidth { spacing *= 2 }
            let grid: Double = _grid(index, document).chars ?? 0
            // (At the run's own width, `w:w` with it: zh-b24b396a's cover
            // title, 22pt at 135% spaced 1pt under Normal's 200
            // firstLineChars, starts 63.4pt in in Word's print, two of
            // 22 × 1.35 + 2 — lab `b24`, and 48 at 100% — where ours
            // took 48 and set "标" on the first line.)
            var wide: Double = first?.style.horizontalScale ?? named?.char.horizontalScale ?? 1
            // (And, in Word for Mac, as the first character is drawn: bold
            // in a face it emboldens is that much wider. Lab tflc, fresh Mac
            // Word, zh-8dc59b5b's "第三条" bold 16pt FangSong under 200: its
            // first line starts 32.65 in, 2 × 16.32; not bold, 32.00; at 100
            // and 300, 16.30 and 48.95; at 15.5 and 12pt, 2 × 15.80 and
            // 2 × 12.23. The mark's size and the grid do nothing.)
            let ownBold: Bool = first?.style.bold ?? false
            let styleBold: Bool = (named?.char.bold ?? false) && !(first?.style.off.contains(.bold) ?? false)
            if !RichTextTheme.wordWindowsPages, ownBold || styleBold {
                let eaName: String? = first?.style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? _normalChar(document)?.eastAsiaFontFamily
                let faceName: String? = eaName ?? first?.style.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily
                if let face = theme.faceResolver?(faceName, true), face.boldSpread > 0 { wide *= 1 + face.boldSpread }
            }
            // (In whole twips, as Word keeps an indent: 2 characters of
            // 14.6465pt are 586 twips, 29.3pt — lab `hc` sets the line as
            // it does `w:firstLine="586"`, not as 29.293.)
            let counted = (chars / 100 * (size * wide + spacing + grid) * 20).rounded() / 20
            // (In Word for Windows the file's own twips, written with the count in the
            // paragraph's own indent, where they stand within 1.5pt of it: Word's print
            // of the corpus, against ours — of 142 paragraphs with `w:firstLineChars`,
            // 105 start where we count them and 37 where the file says, ours 0.2 to
            // 1.1pt off: 23.10 for 200 characters of 12pt YaHei (counted 23.43), 643
            // twips for 16pt FangSong (640). A stored value far from the count is
            // stale, and Word counts: zh-f784cc40's firstLine 640 on 14pt runs
            // starts 28pt in, zh-76700e5f's style-borne 836 and 31680 likewise.
            // zh-360c1df1's first line started 0.15pt early and took the "展" Word
            // refuses.)
            if RichTextTheme.wordWindowsPages, p.style.eastAsian["w:indentStored"] == "1", p.style.firstLineIndent != 0,
               (chars > 0) == (p.style.firstLineIndent > 0),
               abs(abs(p.style.firstLineIndent) - abs(counted)) <= 1.5
                || (grid != 0 && abs(abs(p.style.firstLineIndent) - abs((chars / 100 * (size * wide + spacing) * 20).rounded() / 20)) <= 1.5) {
                return p.style.firstLineIndent - _topLineSqueeze(p, document)
            }
            return counted - _topLineSqueeze(p, document)
        }
        return p.style.firstLineIndent - _topLineSqueeze(p, document)
    }

    /// The paragraph's first run that is not only a drawing's anchor.
    func _firstTextRun(_ p: RichParagraph) -> Run? {
        let units = Array(p.text.utf16)
        var at = 0
        return p.runs.first { r in
            defer { at += r.length }
            return !(at ..< min(units.count, at + r.length)).allSatisfy { units[$0] == 0xFFFC }
        } ?? p.runs.first
    }

    /// What an opening mark at the paragraph's start gives up where the
    /// paragraph compresses punctuation at a line's start (Word's
    /// `w:topLinePunct`): its blank left half, in points. zh-2b955411's
    /// "（六） 对…" in Body Text, which says so, starts 8pt left of its
    /// two-character indent at 16pt, and the line takes one character
    /// more (its "监"). Only where the settings compress punctuation.
    /// (A line inside the paragraph that starts with such a mark is not
    /// done: the first line is where the corpus has them.)
    func _topLineSqueeze(_ p: RichParagraph, _ document: RichDocument) -> Double {
        guard theme.wordRules, p.style.eastAsian["w:topLinePunct"] == "1",
              document.characterSpacingControl?.hasPrefix("compressPunctuation") ?? false,
              let first = p.text.utf16.first, Self._openingUnits.contains(first) else { return 0 }
        let named = _named(p, document)
        let size: Double = p.runs.first?.style.fontSize ?? named?.char.fontSize ?? theme.fontSize
        return size / 2
    }

    /// The sheet's entry for a paragraph: its style's, and for a plain
    /// paragraph Normal's — the face and size a document's body text is
    /// set in when its runs name none, and what its own style leaves
    /// unsaid. (A heading with no entry keeps the theme's look.)
    /// `p` with its first word hidden — up to and with its first space, or
    /// its first character where that is East Asian: what a first line
    /// indented past its cell shows of it (see `_layoutParagraph`).
    static func _hidingFirstWord(_ p: RichParagraph, keeping: Bool = false, characterOnly: Bool = false, unseenCharacter: Bool = false) -> RichParagraph {
        let units = Array(p.text.utf16)
        guard let first = units.first else { return p }
        if unseenCharacter {
            // (The first character kept in its place and drawn clear: it holds its line, as
            // Word's does, and a copy of it stands past the cell — see `_unseenShift`.)
            let n = UTF16.isLeadSurrogate(first) ? 2 : 1
            var q = p
            var runs: [Run] = [], at = 0
            for r in p.runs {
                let end = at + r.length
                if at < n, end > n {
                    var clear = r.style; clear.unseen = true
                    runs.append(Run(length: n - at, style: clear)); runs.append(Run(length: end - n, style: r.style))
                } else if end <= n {
                    var clear = r.style; clear.unseen = true
                    runs.append(Run(length: r.length, style: clear))
                } else { runs.append(r) }
                at = end
            }
            q.runs = runs
            return q
        }
        var n = 1
        if first < 0x2E80, !characterOnly {
            // (Up to a line's break too: a turned box's first line ends after
            // its first character — `_turnedBox`'s U+2028.)
            while n < units.count, units[n - 1] != 0x20, units[n] != 0x2028, units[n] != 0x0A, units[n] != 0x09,
                  units[n] < 0x2E80 || units[n] == 0x20 { n += 1 }
        }
        if characterOnly {
            // (The first character that is text, a drawing's anchor before it not counting: it
            // keeps the line it stands on and draws nothing, so an em space of its
            // own width stands for it.)
            var chars = Array(units)
            guard let start = chars.firstIndex(where: { $0 != 0xFFFC }), !UTF16.isLeadSurrogate(chars[start]) else { return p }
            chars[start] = 0x2003
            var q = p
            q.text = String(decoding: chars, as: UTF16.self)
            return q
        }
        var q = p
        var runs: [Run] = [], at = 0
        for r in p.runs {
            let end = at + r.length
            if at < n, end > n {
                var hidden = r.style; hidden.hidden = true
                runs.append(Run(length: n - at, style: hidden)); runs.append(Run(length: end - n, style: r.style))
            } else if end <= n {
                var hidden = r.style
                // (A paragraph of that word alone: Word's print holds it, clipped by
                // its cell, zh-9bcea239's scores; ours keeps it too, as good as clear.)
                if n >= units.count, keeping, RichTextTheme.wordWindowsPages { hidden.unseen = true } else { hidden.hidden = true }
                runs.append(Run(length: r.length, style: hidden))
            } else {
                runs.append(r)
            }
            at = end
        }
        q.runs = runs
        return q
    }

    /// A paragraph Word shows nothing of: its mark hidden (`w:vanish` on
    /// the mark, or in its paragraph style) and every run hidden. It takes
    /// no room and draws no border — bug59058's HTML "Top of Form"
    /// paragraphs, hidden by their style (z-TopofForm) with a rule under
    /// each, drew two rules and set page 24's text 3.5pt low.
    func _vanishes(_ p: RichParagraph, _ document: RichDocument) -> Bool {
        guard theme.wordRules, p.cell == nil, p.image == nil, p.inlineImages.isEmpty else { return false }
        let named = _named(p, document)
        let styleHides = named?.char.hidden ?? false
        if p.text.isEmpty, p.style.mark?.off.contains(.hidden) == true,
           !p.style.markHidden, p.style.mark?.hidden != true { return false }
        guard p.style.markHidden || (p.style.mark?.hidden ?? styleHides) else { return false }
        if p.text.isEmpty { return styleHides || p.style.markHidden }
        return p.runs.allSatisfy { $0.style.hidden || styleHides }
    }

    func _named(_ p: RichParagraph, _ document: RichDocument) -> RichNamedStyle? {
        guard theme.wordRules else { return document.styles.resolve(p.style) }
        let normal = document.styles[RichNamedStyle.normalId]
        guard var entry = document.styles.resolve(p.style) else { return p.style.heading == nil ? normal : nil }
        // What a style leaves unsaid is Normal's: a sheet read from a
        // file states a style's face and size only where they differ.
        if entry.id != RichNamedStyle.normalId, let n = normal?.char {
            if entry.char.fontSize == nil { entry.char.fontSize = n.fontSize }
            if entry.char.fontFamily == nil { entry.char.fontFamily = n.fontFamily }
            if entry.char.eastAsiaFontFamily == nil { entry.char.eastAsiaFontFamily = n.eastAsiaFontFamily }
            if entry.char.hAnsiFontFamily == nil { entry.char.hAnsiFontFamily = n.hAnsiFontFamily }
            if entry.char.kerningFrom == nil { entry.char.kerningFrom = n.kerningFrom }
        }
        return entry
    }

    /// A table floating at an offset from the margin (no vertical anchor stated) and centred on it, that runs over a page
    /// or more, with room at its left: the paragraph after it stands at the top of the table's last page, beside the
    /// rows there, as Word for Windows prints LibreOffice's floattable-deleted-anchor ("Demo 4" at the margin, y 72, the
    /// table's text from x 236).
    func _splitMarginFloatBeside(_ table: String, _ i: Int, _ page: Int, _ document: RichDocument) -> Bool {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, page > 0, i > 0, _cells[i] == nil, !document.paragraphs[i].text.isEmpty,
              let ts = document.tableStyles[table], ts.marginOffsetY != nil, ts.floatsOverText, !ts.pageAnchored,
              ts.floatX == nil, let kept = ts.keptPosition, kept.containsSubstring("w:tblpXSpec=\"center\""),
              _pages[page].contains(where: { _cells[$0.paragraph]?.table == table }),
              _pages[page - 1].contains(where: { _cells[$0.paragraph]?.table == table }),
              let widths = _columnWidths[table] else { return false }
        let column = _flowWidth(i), width = widths.reduce(0, +)
        return (column - width) / 2 >= _px(theme.fontSize) * 3 + _px(20)
    }

    /// A floating table at the left of the column that leaves a strip at its right for three ems of text, with a narrow
    /// ordinary table after the paragraph `i` (or paragraphs of text) that stand in the strip: the paragraph between
    /// them is beside it too. (lo-5e49366b: a blank line, a 90pt table and "x", all at the top of the strip in Word.)
    func _stripBesideLeftTable(_ table: String, _ i: Int, _ document: RichDocument) -> Bool {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, i + 1 < document.paragraphs.count, let next = document.paragraphs[i + 1].cell,
              _narrowBesideFloat(next.table, document), let ts = document.tableStyles[table], ts.floatsOverText,
              let kept = ts.keptPosition, !kept.containsSubstring("w:tblpXSpec"), let widths = _columnWidths[table] else { return false }
        let column = _flowWidth(i), left = _tableLeft(table, document)
        return left < column / 2 && column - (left + widths.reduce(0, +)) >= _px(theme.fontSize) * 3 + _px(20)
    }

    /// A floating table at the left of the column with room at its right, and an empty paragraph after it that anchors
    /// another floating table: the anchor stands beside the first, and its table is set from there (it may overlap the
    /// first: no tblOverlap says never). lo-e998b55c: Word's second table is 12.9pt under the first's top, ours 70pt.
    func _anchorBesideLeftTable(_ table: String, _ i: Int, _ document: RichDocument) -> Bool {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, i + 1 < document.paragraphs.count, let next = document.paragraphs[i + 1].cell,
              next.table != table, let ns = document.tableStyles[next.table], ns.floatsOverText, ns.keptPosition?.containsSubstring("tblOverlap w:val=\"never\"") != true,
              ns.floatRaiseY != nil || ns.floatOffsetY != nil,
              let ts = document.tableStyles[table], ts.floatsOverText, ts.floatRaiseY != nil || ts.floatOffsetY != nil,
              let kept = ts.keptPosition, !kept.containsSubstring("w:tblpXSpec"), let widths = _columnWidths[table] else { return false }
        let column = _flowWidth(i), left = _tableLeft(table, document)
        return left < column / 2 && column - (left + widths.reduce(0, +)) >= _px(theme.fontSize) * 3 + _px(20)
    }

    /// A table floating by the text with a tblpY under its anchor, and a strip of at least a character at its right: the
    /// empty marks after it keep their lines and the first of them stands at the line the table hangs from, beside it,
    /// the flow going on from there (not from the table's foot). lo-796c371e: Word's twelve empty marks are 25.4pt
    /// apart from the first, two of them at x 537 beside the table; ours took the table's offset on top.
    func _markBesideOffsetFloat(_ table: String, _ i: Int, _ document: RichDocument) -> Bool {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, i > 0, document.paragraphs[i].text.isEmpty,
              let ts = document.tableStyles[table], ts.floatOffsetY != nil || ts.floatRaiseY != nil, ts.floatsOverText, !ts.pageAnchored, let kept = ts.keptPosition,
              kept.containsSubstring("w:vertAnchor=\"text\""), !kept.containsSubstring("w:horzAnchor=\"page\""),
              !kept.containsSubstring("w:tblpXSpec"), let widths = _columnWidths[table] else { return false }
        func twips(_ name: String) -> Double {
            guard let r = kept.rangeOfSubstring("\(name)=\"") else { return 0 }
            return Double(kept[r.upperBound...].prefix { $0 == "-" || $0.isNumber }) ?? 0
        }
        let size = document.paragraphs[i].style.mark?.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
        let strip = _flowWidth(i) - _px(twips("w:tblpX") / 20) - widths.reduce(0, +) - _px(twips("w:rightFromText") / 20)
        return strip >= _px(size)
    }

    /// An ordinary table (not floating, not placed against the page) a fifth of the column wide or less, that Word
    /// sets in the strip beside a floating table rather than under it.
    func _narrowBesideFloat(_ table: String, _ document: RichDocument) -> Bool {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, let ts = document.tableStyles[table], !ts.floatsOverText, !ts.pageAnchored,
              ts.keptPosition == nil, let widths = _columnWidths[table] else { return false }
        return widths.reduce(0, +) <= _px(1) * 100 || _besideWideFloatShift(table, document) != nil
    }

    /// How far right an ordinary table wider than the strip stands to sit beside the floating table that
    /// stands just before it (the float's right side and the distance it asks), or nil where it does not fit
    /// beside it. Word's print of LibreOffice's lo-ce0d5e6d: a 387pt table directly after a tblOverlap-never
    /// floating one of the same width sits level with it, its rules at 417.5, where ours set it under.
    /// (amd-3's patch, carried over the split.)
    func _besideWideFloatShift(_ table: String, _ document: RichDocument) -> Double? {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, let ts = document.tableStyles[table], !ts.floatsOverText, !ts.pageAnchored,
              ts.keptPosition == nil, ts.alignment == .left, let widths = _columnWidths[table],
              let f = _tableFirstParagraph[table], f > 0, f - 1 < _cells.count, let prev = _cells[f - 1]?.table, prev != table,
              let ps = document.tableStyles[prev], ps.floatsOverText, !ps.pageAnchored, let kept = ps.keptPosition,
              kept.containsSubstring("w:vertAnchor=\"text\""), !kept.containsSubstring("w:tblpXSpec"),
              let pw = _columnWidths[prev], let r = kept.rangeOfSubstring("w:rightFromText=\"") else { return nil }
        let distance = Double(kept[r.upperBound...].prefix { $0.isNumber }) ?? 0
        let edge = _tableLeft(prev, document) + pw.reduce(0, +) + _px(distance / 20)
        let own = _px(ts.indent ?? 0)
        guard edge > own + 0.01, edge + widths.reduce(0, +) <= _flowWidth(f) + 0.01 else { return nil }
        return edge - own
    }

    /// A paragraph's left and right indents in points: Word's
    /// `w:leftChars` and `w:rightChars` count characters of the
    /// document's own size (Normal's), and outrank the measure beside
    /// them. On a character grid a character is the grid's: the size
    /// and the grid's addition to it, as for the first line's count —
    /// zh-457a8d62's leftChars 200 at 16pt on a grid of 17.0 starts its
    /// lines 34pt in, in Word's print, where ours were at 32 and a line
    /// 2pt longer took a character Word leaves for the next.
    /// Where the text of paragraph `i` starts, from its own left edge, beside
    /// the table floating by the text that it follows — a narrow one against
    /// the margin with room at its right for a few characters — or nil.
    /// The last cell of the table that floats by the text above paragraph `i`
    /// and the body paragraphs between (a few at most) stand under, with how
    /// far down from the table's anchor the paragraph is.
    func _besideSource(_ i: Int, _ document: RichDocument) -> (cell: _CellGeo, offset: Double)? {
        var offset = 0.0
        var k = i - 1
        while k >= 0, k >= i - 8, k < _cells.count {
            // (Not across a section or a page break: the table stands on the page before. The
            // title of a landscape section, "附件2：", opens the page after a 478pt table of
            // zh-316044fe's, and stands at the margin in Word's print.)
            if k + 1 < _pageBreak.count, _pageBreak[k + 1] { return nil }
            if k + 1 < _sectionOf.count, _sectionOf[k + 1] != _sectionOf[k] { return nil }
            if let c = _cells[k] {
                // (An ordinary narrow table in the strip beside a floating one is no cover for it: what follows
                // stands beside the float still. LibreOffice's lo-5e49366b, a 90pt table and "x" after a 350pt float.)
                if _narrowBesideFloat(c.table, document) {
                    var j = k
                    while j > 0, let d = _cells[j - 1], d.table == c.table { j -= 1 }
                    k = j - 1
                    continue
                }
                return (c, offset)
            }
            guard k < _heights.count else { return nil }
            offset += _heights[k]
            k -= 1
        }
        return nil
    }

    func _besideIndent(_ i: Int, _ p: RichParagraph, _ document: RichDocument, table: String? = nil) -> (indent: Double, right: Bool)? {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, p.cell == nil, i > 0, !p.text.isEmpty, p.image == nil,
              !p.style.clearsFloat,
              let source = table ?? _besideSource(i, document)?.cell.table,
              let ts = document.tableStyles[source], ts.floatsOverText, !ts.pageAnchored,
              let kept = ts.keptPosition, kept.containsSubstring("w:vertAnchor=\"text\""),
              let widths = _columnWidths[source] else { return nil }
        // (A table set at the right margin, `w:tblpXSpec="right"`, takes the text at its left
        // as one placed across does; and a list's items stand there too: lo-717ff943's
        // bullets beside its right-hand table of albums, tdf97090.)
        let rightAligned = kept.containsSubstring("w:tblpXSpec=\"right\"")
        guard rightAligned || !kept.containsSubstring("w:tblpXSpec"), rightAligned || p.style.list == nil else { return nil }
        func twips(_ name: String) -> Double {
            guard let r = kept.rangeOfSubstring("\(name)=\"") else { return 0 }
            return Double(kept[r.upperBound...].prefix { $0 == "-" || $0.isNumber }) ?? 0
        }
        let column = _flowWidth(i)
        let left = _tableLeft(source, document)
        let right = left + widths.reduce(0, +)
        // The text's edge: the table's right side and the clear it asks.
        // (Before 2013's layout the text keeps off the table's right cell margin too: lab
        // `beside-float`, Word's print of a 50% to 90% table with 141-twip distances, sets
        // the text 5.3pt past where the distance alone puts it, at every width.)
        // (… with a distance under 10pt only: lo-f48e444e's 14.2pt distance puts the text
        // exactly that far from the table in Word's print, 390.3, where the outdent
        // as well put ours at 395.4.)
        // (From the table's outer edge, its right rule's outer half too, where Word's rules are
        // followed: lo-e1104feb's 40% table, 3pt rules, sets its text 181.6 in Word's print, its
        // right rule centred at 171.0 and the distance 9pt.)
        let ruleHalf: Double = theme.wordRules && ts.borders ? _px((ts.edgeWidths["right"] ?? ts.borderWidth ?? 0.5) / 2) : 0
        let edge = right + ruleHalf + _px(twips("w:rightFromText") / 20)
            + ((document.compatibilityMode ?? 0) < 15 && twips("w:rightFromText") < 200 ? _px(document.tableStyles[source]?.textOutdentRight ?? 5.4) : 0)
        let size = _px(p.runs.first?.style.fontSize ?? theme.fontSize)
        // (A table in the left half, or one that fills most of the column, whose
        // text beside it in the strip left at its right is a few words wide:
        // LibreOffice's floattable-move-master, a 8075-twip table in a 9362
        // column, has "He tried to nervously tap his way" in the 1100 twips
        // beside it in Word's print. One two-thirds of a wide column leaves
        // the text under it: zh-ae2dd08d90a's 9801-twip table on a landscape
        // page.)
        let own = _px(p.style.indentLeft)
        // (The side with the room: a table in the right half with no room at its right
        // for text and room at its left for three ems: the lines end short of it, by a
        // right indent. Word sets LibreOffice's tdf164500 "Easier net order..." in the
        // 295pt strip left of its table at x 376, and tdf164474-like lo-4c84a541's
        // "After table1" at the margin, 207pt left of a table at tblpX 5597, with more
        // room at its left than its right.)
        let gap = left - _px(twips("w:leftFromText") / 20)
        let leftRoom = gap - own
        let rightRoom = column - edge - _px(p.style.indentRight)
        if leftRoom >= size * 3, leftRoom > rightRoom, left >= column / 2 || leftRoom > rightRoom + size * 3 {
            let narrow = column - gap - _px(p.style.indentRight)
            return narrow > 0 ? (narrow, true) : nil
        }
        // (Beside a table at the left, in the strip at its right: one that ends in the middle
        // of the column leaves the text under it, and so does one that fills most of it.)
        guard left < column / 2, rightRoom >= size * 3 else { return nil }
        return edge > own ? (edge - own, false) : nil
    }

    /// The square-wrapped float at the left of paragraph `i`'s text — a drop
    /// cap's box, a picture at the margin, a table floating in its cell — as
    /// how far the lines level with it start in from the paragraph's left, and
    /// the stretch of the paragraph's height it takes; nil for none. It is
    /// anchored in the paragraph itself or in one of the few before it in the
    /// same cell (or the body), the paragraphs between standing under it.
    func _besideOwn(_ i: Int, _ p: RichParagraph, _ document: RichDocument) -> (indent: Double, band: (top: Double, bottom: Double), right: Bool, leftRoom: Double?)? {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, !p.text.isEmpty else { return nil }
        // (A picture in the header that wraps the text and stands the page's height: every
        // line of the body starts past it. See `PageSetup.headerWrapLeft`.)
        if p.cell == nil, p.style.list == nil, i >= 0 {
            let wrapLeft = _setup(ofParagraph: i).headerWrapLeft
            let inset = _px(wrapLeft) - _px(p.style.indentLeft)
            if wrapLeft > 0, inset > 0 { return (inset, (-1, 1e9), false, nil) }
        }
        // (A cell's text is as wide as the cell less its margins, not the page's
        // column.)
        let cell = p.cell != nil && i < _cells.count ? _cells[i] : nil
        let inner = cell.map { max(0, $0.colWidth - $0.pad.left - $0.pad.right) } ?? _flowWidth(i)
        let size = _px(p.runs.first?.style.fontSize ?? theme.fontSize)
        var best: (indent: Double, band: (top: Double, bottom: Double), right: Bool, leftRoom: Double?)?
        var boxes: [(top: Double, bottom: Double, left: Double, right: Double)] = []
        _besideBoxes[i] = nil
        _besideStartLeft[i] = nil
        var startLeft: (indent: Double, band: (top: Double, bottom: Double))?
        defer { if best?.right == true, best?.leftRoom == nil, let sl = startLeft, theme.wordRules, RichTextTheme.wordWindowsPages { _besideStartLeft[i] = sl } }
        defer { if boxes.count >= 2, best?.leftRoom != nil { _besideBoxes[i] = boxes } }
        var offset = 0.0
        var k = i
        while k >= 0, k >= i - 6 {
            let q = document.paragraphs[k]
            if k < i {
                guard q.cell == p.cell, k < _heights.count else { break }
                // (A picture on an earlier page does not narrow this one: the paragraph that opens
                // a page, or a section, stands clear of what is anchored before it.)
                if k + 1 < _pageBreak.count, _pageBreak[k + 1] { break }
                if k + 1 < _sectionOf.count, _sectionOf[k + 1] != _sectionOf[k] { break }
            }
            // (One anchored in a paragraph above is wrapped round too, for a paragraph that is no
            // list item: a list item's label asks its own room beside a tight picture, see
            // zh-f2ca3070.)
            var candidates: [(image: ImageAttachment, size: Size?)] = k == i || p.style.list == nil ? q.inlineImages.inOrder.map { ($0, nil) } : []
            // (A table floating in the cell, in a paragraph of its own above: the
            // text that follows stands beside it. A picture anchored in an earlier
            // paragraph is left to the paragraph-by-paragraph push, as before:
            // zh-37b6536f's photographs.)
            if k < i, p.cell != nil, let image = q.image, image.name == "table", k < _imageSize.count { candidates.append((image, _imageSize[k])) }
            for (image, laid) in candidates {
                // (A box in the middle of the column with room on both sides, text
                // wrapped round it on both: the lines alternate between the room
                // at its left and the room at its right, a left piece and a
                // right piece on one line of the page. Lab-less: Word's print of
                // LibreOffice's tdf133924, "Around", and tdf135665's objects.)
                if k == i || p.style.list == nil, p.cell == nil, let float = image.float, float.wraps, !float.takesRoom, float.wrapSide == nil,
                   float.verticalAlign == nil, float.verticalFrom == "paragraph",
                   float.horizontalAlign == nil || ["left", "center", "right"].contains(float.horizontalAlign!),
                   ["column", "margin", "page"].contains(float.horizontalFrom), _perSection == false || float.horizontalFrom != "margin" {
                    if image.textBox?.fitsText == true { _ = _textBox(image, document) }
                    let w = laid.map { $0.width }
                        ?? min(_px(image.width), image.textBox.flatMap { _fitWidths["\(image.id)|\($0.hashValue)"] } ?? .infinity)
                    let h = laid.map { $0.height } ?? _px(image.height)
                    var bandLeft = 0.0, bandWidth = inner
                    if float.horizontalFrom == "page" {
                        let setup = _setup(ofParagraph: i)
                        let left = _px(setup.marginLeft + setup.gutter)
                        bandLeft = -left
                        bandWidth = inner + left + _px(setup.marginRight)
                    }
                    let x: Double
                    switch float.horizontalAlign {
                    case "center": x = bandLeft + (bandWidth - w) / 2
                    case "right": x = bandLeft + bandWidth - w
                    case "left": x = bandLeft
                    default: x = bandLeft + _px(float.x)
                    }
                    let own = _px(p.style.indentLeft)
                    let rightGap = _px(p.style.indentRight)
                    let leftEdge = x - _px(float.distanceLeft ?? 9), rightEdge = x + w + _px(float.distanceRight ?? 9)
                    // (Room at its left for a character and a half is enough: lab `anc` D (Word for Windows, 12pt,
                    // a 40pt square at x 20 from the column's edge, no gap) sets "D-" in the 20pt strip and "p3"
                    // after the picture, on each of the three lines it spans; the room was three ems.)
                    if w > 0, leftEdge - own > 0.5, inner - rightEdge - rightGap >= size * 3 {
                        let band = (top: _px(float.y) - _px(float.distanceTop) - offset,
                                    bottom: _px(float.y) + h + _px(float.effectBottom) + _px(float.distanceBottom) - offset)
                        if band.bottom > 0.01 { boxes.append((band.top, band.bottom, leftEdge - own, rightEdge - own)) }
                        if band.bottom > 0.01, best == nil || rightEdge - own > best!.indent { best = (rightEdge - own, band, false, leftEdge - own) }
                        continue
                    }
                    // (A thin box standing at the line start, in a paragraph with several boxes (the other one mid-column, so only one wins best):
                    // the lines step past it at the start as well, so its blocked stretch is kept in boxes.
                    // Word's print of dx2 28abf02c, its bracket groups: the wrapped lines start at 74.8, the group's right
                    // edge and gap past the margin, not at the indent.)
                    if w > 0, leftEdge - own <= 0.5, rightEdge - own > 0.5, candidates.count > 1 {
                        let band = (top: _px(float.y) - _px(float.distanceTop) - offset,
                                    bottom: _px(float.y) + h + _px(float.effectBottom) + _px(float.distanceBottom) - offset)
                        if band.bottom > 0.01 { boxes.append((band.top, band.bottom, 0, rightEdge - own)) }
                        if band.bottom > 0.01, startLeft == nil || rightEdge - own > startLeft!.indent { startLeft = (rightEdge - own, band) }
                    }
                }
                guard let float = image.float, float.wraps, !float.takesRoom, float.verticalAlign == nil, float.verticalFrom == "paragraph",
                      float.horizontalAlign == nil || float.horizontalAlign == "left" || float.horizontalAlign == "right" else { continue }
                let inCell = float.horizontalFrom == "cell" && cell != nil
                guard inCell || float.horizontalFrom == "column" || (float.horizontalFrom == "margin" && p.cell == nil) else { continue }
                let column = inCell ? (cell?.colWidth ?? 0) : inner
                // (A box that takes its text's width is that wide: a drop cap's.)
                if image.textBox?.fitsText == true { _ = _textBox(image, document) }
                let w = laid.map { $0.width }
                    ?? min(_px(image.width), image.textBox.flatMap { _fitWidths["\(image.id)|\($0.hashValue)"] } ?? .infinity)
                let h = laid.map { $0.height } ?? _px(image.height)
                var x = float.horizontalAlign == "right" ? column - w : float.horizontalAlign == "left" ? 0 : _px(float.x)
                // (Word clamps a square or tight box that sits left of its table cell to the cell's text edge, and the text stands beside it:
                // e86e26f7's picture, 108 pt left of its cell; lab e86-picwrap. wrapNone/behind keep the offset.)
                if theme.wordRules, cell != nil, float.horizontalFrom == "column", float.horizontalAlign == nil, x < _px(image.effectLeft) { x = _px(image.effectLeft) }
                // (A list item's text starts at its numbering's left: the lines beside the
                // box start at its edge, not at that and the edge's whole.)
                let listLeft = k == i ? _listIndents(p, document).map { _px($0.left) } ?? 0 : 0
                if listLeft > _px(p.style.indentLeft) + 0.01 { RuleTrace.hit("word-beside-box-counts-the-list-left") }
                let own = max(_px(p.style.indentLeft), listLeft) + (inCell ? (cell?.pad.left ?? 0) : 0)
                let rightGap = _px(p.style.indentRight) + (inCell ? (cell?.pad.right ?? 0) : 0)
                guard w > 0 else { continue }
                if x + w / 2 >= column / 2 {
                    // (At the right, with room at its left for three ems and none
                    // at its right: the lines end short of it, by a right indent.
                    // One wrapped on its left alone is left to the paragraph-by-
                    // paragraph push, as before.)
                    guard float.wrapSide != "right",
                          float.wrapSide == "largest" || column - (x + w) - _px(float.distanceRight ?? 9) < size,
                          x - _px(float.distanceLeft ?? 9) - own >= size * 3 else { continue }
                    let narrow = column - rightGap - (x - _px(float.distanceLeft ?? 9))
                    guard narrow > 0 else { continue }
                    let band = (top: _px(float.y) - _px(float.distanceTop) - offset,
                                bottom: _px(float.y) + h + _px(float.effectBottom) + _px(float.distanceBottom) - offset)
                    guard band.bottom > 0.01 else { continue }
                    if best == nil || narrow > best!.indent { best = (narrow, band, true, nil) }
                    continue
                }
                // (Not with room at its left for text: that stands round it on
                // both sides, which the engine does not set.)
                guard float.wrapSide != "left", float.wrapSide == "largest" || x - _px(float.distanceLeft ?? 9) - own < size else { continue }
                let edge = x + w + _px(float.distanceRight ?? 9)
                // (And room at its right for text: across the column it leaves
                // none, and the paragraph goes under it as before.)
                guard edge > own, column - edge - rightGap >= size * 3 else { continue }
                let band = (top: _px(float.y) - _px(float.distanceTop) + _px(float.wrapTopSkip) - offset,
                            bottom: _px(float.y) + h + _px(float.effectBottom) + _px(float.distanceBottom) - offset)
                // (One that ends above this paragraph's top has nothing to do with it.)
                guard band.bottom > 0.01 else { continue }
                if best == nil || edge - own > best!.indent { best = (edge - own, band, false, nil) }
            }
            if k > 0 { offset += _heights[k - 1] }
            k -= 1
        }
        return best
    }

    /// The first page (up to `page`) that holds rows of table `t`; `page` itself for
    /// all but text beside it.
    func _beside_firstPage(of t: String, upTo page: Int, text: Bool) -> Int {
        guard text, theme.wordRules, RichTextTheme.wordWindowsPages else { return page }
        for q in 0 ..< page where _pages[q].contains(where: { _cells[$0.paragraph]?.table == t && !$0.repeated }) { return q }
        return page
    }

    /// The vertical stretch, from paragraph `i`'s top, that the table floating
    /// by the text it follows takes: its offset down to its foot.
    func _besideBand(_ i: Int, _ document: RichDocument) -> (top: Double, bottom: Double)? {
        if let used = _besideBandUse[i] { return used }
        guard i > 0, let source = _besideSource(i, document), case let before = source.cell,
              let style = document.tableStyles[before.table], style.floatsOverText else { return nil }
        let down = style.floatOffsetY ?? 0
        var k = i - 1, top = Double.infinity, bottom = 0.0
        while k >= 0, _cells[k] == nil { k -= 1 }
        while k >= 0, let d = _cells[k], d.table == before.table {
            top = min(top, d.rowTop)
            bottom = max(bottom, d.rowTop + d.ownRowHeight)
            k -= 1
        }
        guard bottom > top else { return nil }
        var band = (top: _px(down) - source.offset, bottom: _px(down) + bottom - top - source.offset)
        // (A table at the right margin that hangs from the same anchor as the one before it, set
        // above the anchor's line, stands over the other's: the text beside them is held in by
        // both, from the higher one's top to the lower one's foot. lo-717ff943, tdf97090: its
        // heading and bullets keep out of the 300pt table of albums from the "Издания Echoes:"
        // table at its head down to its last row.)
        if RichTextTheme.wordWindowsPages, style.floatOffsetY == nil, let raise = style.floatRaiseY, !style.pageAnchored, k >= 0,
           let d = _cells[k], d.table != before.table, let first = document.tableStyles[d.table], first.floatsOverText, !first.pageAnchored,
           let firstDown = first.floatOffsetY {
            var t = Double.infinity, b = 0.0, m = k
            while m >= 0, let e = _cells[m], e.table == d.table { t = min(t, e.rowTop); b = max(b, e.rowTop + e.ownRowHeight); m -= 1 }
            if b > t {
                RuleTrace.hit("word-text-beside-two-floats-hung-from-one-anchor-keeps-out-of-both")
                _besideUnion.insert(i)
                band = (min(_px(down) - _px(raise), _px(firstDown)) - source.offset, max(band.bottom + source.offset, _px(firstDown) + b - t) - source.offset)
            }
        }
        return band
    }

    func _sideIndents(_ p: RichParagraph, at index: Int? = nil, _ document: RichDocument) -> (left: Double, right: Double) {
        var left = p.style.indentLeft, right = p.style.indentRight
        guard theme.wordRules, !p.style.eastAsian.isEmpty else { return (left, right) }
        let unit = ((document.styles[RichNamedStyle.normalId]?.char.fontSize ?? theme.fontSize) + (_grid(index, document).chars ?? 0)) / 100
        // (With a hanging indent the count is from where the first line
        // hangs: the left indent is the count and the hanging one
        // together — as `w:left` beside them says in 420 of the sample's
        // 422 such paragraphs with the hanging in characters, and in all
        // 107 of the corpus's with it in twips alone. zh-89385c94's cells
        // say leftChars -45 and hangingChars 280 at 14pt: text at 33.8pt
        // from the margin, the first line at -5.4; zh-e0ca7252's
        // "（六）前款情形…", leftChars 100 and hanging 567 at 12pt, has its
        // first line 12pt in and the rest 40.35, as w:left 807 says.)
        if let c = Double(p.style.eastAsian["w:leftChars"] ?? p.style.eastAsian["w:startChars"] ?? ""), c != 0 {
            left = (c * unit * 20).rounded() / 20
            left += max(0, -firstLineIndent(p, document))
        }
        if let c = Double(p.style.eastAsian["w:rightChars"] ?? p.style.eastAsian["w:endChars"] ?? ""), c != 0 { right = (c * unit * 20).rounded() / 20 }
        // (A left indent past the column leaves the text nowhere, and Word
        // takes the hanging one for it, the first line at the margin:
        // zh-60c80728's table note "注：1.…", w:left 31680 (22 inches, the
        // most Word allows) with hangingChars 200 at 10.5pt, stands at the
        // margin in Word's print and runs on 21pt in; ours had no room
        // for it, and the notes after it went to a page of their own.)
        if let index, _px(left) >= _flowWidth(index) { left = max(0, -firstLineIndent(p, document)) }
        return (left, right)
    }

    /// 1 when paragraph `i`'s painter has the indent's box before the
    /// text: what to add to a paragraph offset to get the painter's.
    func _lead(_ i: Int) -> Int {
        i < _leadWidth.count && _leadWidth[i] != 0 ? 1 : 0
    }

    func _map(_ i: Int) -> _OffsetMap {
        _OffsetMap(lead: _lead(i), inserts: i < _inserts.count ? _inserts[i] : [])
    }

    /// Where each of a painter's lines starts, in paragraph offsets.
    func _lineStarts(_ painter: TextPainter, _ map: _OffsetMap, count: Int) -> [Int] {
        let total = count + map.lead + map.inserts.count
        var out: [Int] = []
        var at = 0
        while at < total {
            let r = painter.getLineBoundary(TextPosition(offset: at))
            let start = min(count, map.paragraph(max(r.start, at)))
            if out.last != start { out.append(start) }
            // (A line the engine reports as ending where it stands — one
            // that closes on a zero-width space — is stepped past, not
            // taken for the last.)
            guard r.end > at || r.end > r.start else { break }
            at = max(r.end, at + 1)
        }
        return out
    }

    /// The spaces of a paragraph (UTF-16 offsets) that stand beside East
    /// Asian text inside a line: every run of them with an ideograph,
    /// kana or full-width mark on either side, but one that ends the
    /// paragraph, a line break, or a line of the layout at hand.
    func _spacesToHold(_ p: RichParagraph, lineStarts: Set<Int>) -> Set<Int> {
        var out: Set<Int> = []
        var at = 0
        var run: [Int] = []
        var left: Character? = nil
        func wide(_ c: Character?) -> Bool { c.map { Self.isEastAsian($0, hinted: false) } ?? false }
        for ch in p.text {
            if ch == " " {
                run.append(at)
            } else {
                // (And the spaces a paragraph opens with, whatever follows:
                // Word keeps them at their width in a justified line and
                // stretches the line elsewhere. zh-b378d8c4's "    9.化工：…",
                // 14pt under balanced widths, has its four spaces 7pt apiece
                // in Word's print, "9" at 107.4; the engine took them as the
                // line's stretch, down to nothing, and set "9" at 80.4.)
                // (A Hangul word kept whole at the line end (hangul-word-held-whole) has no stretch points inside
                // it, so the spaces between Hangul words stay plain and take the line's stretch, as Word's do.)
                let hangulGap = theme.wordRules && RichTextTheme.wordWindowsPages && run.first != 0
                    && (left?.unicodeScalars.first).map({ $0.value >= 0xAC00 && $0.value <= 0xD7A3 }) == true
                    && (ch.unicodeScalars.first).map({ $0.value >= 0xAC00 && $0.value <= 0xD7A3 }) == true
                if let end = run.last, ch != "\n", ch != "\u{2028}", wide(left) || wide(ch) || run.first == 0 || Self._opensAfterBreak(left, theme), !hangulGap, !lineStarts.contains(end + 1) { out.formUnion(run) }
                run = []
                left = ch
            }
            at += ch.utf16.count
        }
        return out
    }

    /// A run of spaces that opens a line after a manual break: Word draws each at its width.
    @inline(never)
    static func _opensAfterBreak(_ left: Character?, _ theme: RichTextTheme) -> Bool {
        theme.wordRules && RichTextTheme.wordWindowsPages && (left == "\n" || left == "\u{2028}")
    }

    /// Whether the held spaces include a run opening a line after a manual break. Those take
    /// room in Word, so the lines may then break differently from the plain layout, and the
    /// held layout stands even when its line starts differ.
    @inline(never)
    static func _holdsBreakOpening(_ p: RichParagraph, _ hold: Set<Int>, _ theme: RichTextTheme) -> Bool {
        guard theme.wordRules, RichTextTheme.wordWindowsPages else { return false }
        let u = Array(p.text.utf16)
        for k in hold where k < u.count {
            var j = k
            while j > 0, u[j - 1] == 0x20 { j -= 1 }
            if j == 0 { continue }
            if j < k, u[j - 1] == 0x0A || u[j - 1] == 0x2028 { return true }
        }
        return false
    }

    /// How wide a face sets a space, in pixels, at a style's size.
    func _spaceWidth(_ style: TextStyle) -> Double { _glyphWidth(style, " ") }

    /// How wide a face sets a character, in pixels, at a style's size.
    /// `ch`'s advance before `next`, their kerning in it.
    func _pairAdvance(_ style: TextStyle, _ ch: Character, _ next: Character) -> Double {
        let key = "\(ch)\(next)|pair|\(style.fontFamily ?? "")|\(style.fontSize ?? 0)|\(style.fontWeight == .bold)|\(style.fontStyle == .italic)"
        if let w = _spaceWidths[key] { return w }
        func width(_ text: String) -> Double {
            let t = TextPainter(text: TextSpan(text: text, style: style.copyWith(letterSpacing: 0)), textDirection: .ltr)
            t.layout(minWidth: 0, maxWidth: 100_000)
            defer { t.dispose() }
            return t.width
        }
        let w = width("\(ch)\(next)") - width("\(next)")
        _spaceWidths[key] = w
        return w
    }

    func _glyphWidth(_ style: TextStyle, _ ch: Character) -> Double {
        let key = "\(ch)|\(style.fontFamily ?? "")|\(style.fontSize ?? 0)|\(style.fontWeight == .bold)|\(style.fontStyle == .italic)"
            + (style.fontFeatures?.isEmpty ?? true ? "" : "|f")
        if let w = _spaceWidths[key] { return w }
        func width(_ text: String) -> Double {
            let t = TextPainter(text: TextSpan(text: text, style: style.copyWith(letterSpacing: 0)), textDirection: .ltr)
            t.layout(minWidth: 0, maxWidth: 100_000)
            defer { t.dispose() }
            return t.width
        }
        let w = width("x\(ch)x") - width("xx")
        _spaceWidths[key] = w
        return w
    }
    /// How many glyphs the engine draws `ch` in (at least 1): what a
    /// spacing on it is taken that many times by, the engine spacing
    /// each glyph of a cluster.
    func _glyphCount(_ style: TextStyle, _ ch: Character) -> Int {
        let key = "\(ch)|\(style.fontFamily ?? "")|\(style.fontWeight == .bold)|\(style.fontStyle == .italic)"
        if let n = _glyphCounts[key] { return n }
        func width(_ spacing: Double) -> Double {
            let t = TextPainter(text: TextSpan(text: String(ch), style: style.copyWith(letterSpacing: spacing)), textDirection: .ltr)
            t.layout(minWidth: 0, maxWidth: 100_000)
            defer { t.dispose() }
            return t.width
        }
        let n = max(1, Int((width(10) - width(0)) / 10 + 0.5))
        _glyphCounts[key] = n
        return n
    }

    /// A word as the stand-in shapes it, right to left, unspaced.
    func _wordWidth(_ style: TextStyle, _ word: String) -> Double {
        let key = "\(word)|\(style.fontFamily ?? "")|\(style.fontSize ?? 0)|\(style.fontWeight == .bold)|\(style.fontStyle == .italic)"
        if let w = _wordWidths[key] { return w }
        let t = TextPainter(text: TextSpan(text: word, style: style.copyWith(letterSpacing: 0)), textDirection: .rtl)
        t.layout(minWidth: 0, maxWidth: 100_000)
        defer { t.dispose() }
        _wordWidths[key] = t.width
        return t.width
    }

    /// Paints a paragraph that has characters of a scale of their own
    /// (`CharStyle.horizontalScale`, Word's `w:w`) and says so — false
    /// where it has none. The engine sets no face narrower than it is:
    /// such a stretch is laid out that much smaller or larger a size,
    /// which gives every character its width and every line its
    /// breaks. A paragraph all of one scale — a letterhead at 34%, a
    /// style at 95% — is drawn from a second painter instead: the same
    /// text at its full size in a column that much wider, under a
    /// canvas that much narrower, so that a 61pt letterhead is 61pt
    /// tall and a third as wide rather than 21pt text. One of several
    /// scales has each stretch pulled back to its height about its
    /// line's baseline.
    func _paintScaled(_ i: Int, _ g: ParagraphGeometry, _ canvas: any Canvas, _ document: RichDocument) -> Bool {
        guard theme.wordRules, i < document.paragraphs.count else { return false }
        let p = document.paragraphs[i]
        let named = _named(p, document)
        let sheet = named?.char.horizontalScale
        guard p.image == nil, sheet != nil || p.runs.contains(where: { $0.style.horizontalScale != nil }) else { return false }
        func scale(of run: Run) -> Double {
            let latin = run.style.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily
            return max(0.01, RichTextTheme.wordWidthScale(run.style.horizontalScale ?? sheet ?? 1, wordRules: true,
                                                          eastAsiaFamily: run.style.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? latin))
        }
        let scales = Set(p.runs.filter { $0.length > 0 && $0.style.inlineImage == nil }.map { scale(of: $0) })
        guard scales.contains(where: { abs($0 - 1) > 0.001 }) else { return false }
        let lines = g.painter.computeLineMetrics()
        guard !lines.isEmpty else { return false }
        if scales.count == 1, let k = scales.first, let wide = _widePainter(g.painter, k) {
            let wideLines = wide.computeLineMetrics()
            if wideLines.count == lines.count,
               !zip(wideLines, lines).contains(where: { abs($0.width * k - $1.width) > max(2, $1.width * 0.01) }) {
                canvas.save()
                // (Its baseline where the paragraph's own is.)
                canvas.translate(g.textLeft, g.inkTop + lines[0].baseline - wideLines[0].baseline)
                canvas.scale(k, 1)
                wide.paint(canvas, Offset.zero)
                canvas.restore()
                return true
            }
        }
        // (Each stretch's boxes, joined where they follow on a line.)
        let map = _map(i)
        var pieces: [(rect: Rect, baseline: Double, k: Double)] = []
        var at = 0
        for run in p.runs {
            let from = at
            at += run.length
            let k = scale(of: run)
            guard run.length > 0, abs(k - 1) > 0.001, run.style.inlineImage == nil else { continue }
            let boxes = g.painter.getBoxesForSelection(
                TextSelection(baseOffset: map.painter(from), extentOffset: map.painter(at)), boxHeightStyle: .max)
            for box in boxes where box.right - box.left > 0.01 {
                let mid = (box.top + box.bottom) / 2
                var n = 0
                for (j, line) in lines.enumerated() where mid >= line.baseline - line.ascent - 0.5 { n = j }
                let line = lines[n]
                // (A line's whole band, and all the way out where the
                // stretch ends the line: an overhang is not cut.)
                let top = n == 0 ? -100_000 : lines[n - 1].baseline + lines[n - 1].descent
                let bottom = n == lines.count - 1 ? 100_000 : line.baseline + line.descent
                let left = box.left <= line.left + 0.5 ? -100_000 : box.left
                let right = box.right >= line.left + line.width - 0.5 ? 100_000 : box.right
                if let last = pieces.last, last.k == k, last.baseline == line.baseline, left - last.rect.right < (box.bottom - box.top) / 2 {
                    pieces[pieces.count - 1].rect = Rect.fromLTRB(last.rect.left, top, right, bottom)
                } else {
                    pieces.append((Rect.fromLTRB(left, top, right, bottom), line.baseline, k))
                }
            }
        }
        // (Every piece draws the paragraph again under its clip: a few
        // stretches, not a page of them.)
        guard !pieces.isEmpty, pieces.count <= 6 else { return false }
        // (Each pass with the other pass's text clear, which the canvas
        // drops: a clip hides what it cuts away and a PDF still holds
        // it, so the text read from zh-701eda18's print had every
        // squeezed character twice — "手語翻譯及手語翻譯".)
        var squeezed: [Range<Int>] = []
        var plain: [Range<Int>] = []
        at = 0
        for run in p.runs {
            let from = at
            at += run.length
            guard run.length > 0 else { continue }
            let range = map.painter(from)..<map.painter(at)
            if abs(scale(of: run) - 1) > 0.001, run.style.inlineImage == nil { squeezed.append(range) } else { plain.append(range) }
        }
        let unsqueezed = _clearedPainter(g.painter, squeezed, key: 0)
        let onlySqueezed = _clearedPainter(g.painter, plain, key: 1)
        let origin = Offset(g.textLeft, g.inkTop)
        canvas.save()
        for piece in pieces { canvas.clipRect(piece.rect.shift(origin), clipOp: .difference, doAntiAlias: false) }
        (unsqueezed ?? g.painter).paint(canvas, origin)
        canvas.restore()
        for piece in pieces {
            canvas.save()
            canvas.translate(0, origin.dy + piece.baseline)
            canvas.scale(1, 1 / piece.k)
            canvas.translate(0, -(origin.dy + piece.baseline))
            canvas.clipRect(piece.rect.shift(origin), clipOp: .intersect, doAntiAlias: false)
            (onlySqueezed ?? g.painter).paint(canvas, origin)
            canvas.restore()
        }
        return true
    }

    /// `painter` again with the text in `ranges` (its own offsets)
    /// clear — laid out as it is, drawn as nothing. nil where a line
    /// would come out other than it did. Kept while the painter is.
    func _clearedPainter(_ painter: TextPainter, _ ranges: [Range<Int>], key: Int,
                                 clearBackgroundAndDecoration: Bool = false) -> TextPainter? {
        let id = ObjectIdentifier(painter)
        if let hit = _clearedPainters[id]?[key], hit.source === painter { return hit.cleared }
        guard !ranges.isEmpty, let root = painter.text else { return nil }
        // Adding the second mask for this painter must not dispose the
        // first mask that the caller is about to draw.
        if _clearedPainters.count > 256, _clearedPainters[id] == nil {
            for entries in _clearedPainters.values { for entry in entries.values { entry.cleared.dispose() } }
            _clearedPainters = [:]
        }
        let transparent = Paint(); transparent.color = Color(0x00000000)
        let clear = TextStyle(foreground: transparent,
                              background: clearBackgroundAndDecoration ? transparent : nil,
                              shadows: [], decoration: clearBackgroundAndDecoration ? TextDecoration.none : nil,
                              decorationColor: clearBackgroundAndDecoration ? Color(0x00000000) : nil)
        var at = 0
        func copy(_ span: InlineSpan) -> InlineSpan {
            guard let t = span as? TextSpan else {
                at += 1
                return span
            }
            var parts: [InlineSpan] = []
            if let text = t.text {
                let units = Array(text.utf16)
                var from = 0
                while from < units.count {
                    let here = at + from
                    let inside = ranges.contains { $0.contains(here) }
                    var to = from + 1
                    while to < units.count, ranges.contains(where: { $0.contains(at + to) }) == inside { to += 1 }
                    let piece = String(decoding: units[from..<to], as: UTF16.self)
                    parts.append(TextSpan(text: piece, style: inside ? clear : nil))
                    from = to
                }
                at += units.count
            }
            for child in t.children ?? [] { parts.append(copy(child)) }
            return TextSpan(children: parts, style: t.style, locale: t.locale)
        }
        let cleared = TextPainter(text: copy(root), textAlign: painter.textAlign, textDirection: painter.textDirection ?? .ltr,
                                  strutStyle: painter.strutStyle)
        cleared.fractionalLineHeights = painter.fractionalLineHeights
        if let dims = painter.placeholderDimensions { cleared.setPlaceholderDimensions(dims) }
        cleared.layout(minWidth: painter.width, maxWidth: painter.width)
        let lines = painter.computeLineMetrics(), again = cleared.computeLineMetrics()
        guard lines.count == again.count,
              !zip(lines, again).contains(where: { abs($0.width - $1.width) > 0.01 || abs($0.baseline - $1.baseline) > 0.01 }) else {
            cleared.dispose()
            return nil
        }
        _clearedPainters[id, default: [:]][key] = (painter, cleared)
        return cleared
    }

    /// `painter`'s text at 1/k its size in a column 1/k its width: what
    /// a canvas k as wide draws as characters of that scale. Kept while
    /// the painter is.
    func _widePainter(_ painter: TextPainter, _ k: Double) -> TextPainter? {
        let id = ObjectIdentifier(painter)
        if let hit = _widePainters[id], hit.source === painter { return hit.wide }
        guard let root = painter.text else { return nil }
        if _widePainters.count > 256 {
            for entry in _widePainters.values { entry.wide.dispose() }
            _widePainters = [:]
        }
        func widened(_ style: TextStyle?) -> TextStyle? {
            guard let style, let size = style.fontSize else { return style }
            // (The same line: its height is a multiple of the size.)
            return style.copyWith(fontSize: size / k, letterSpacing: style.letterSpacing.map { $0 / k },
                                  height: style.height.map { $0 * k })
        }
        func copy(_ span: InlineSpan) -> InlineSpan {
            if let image = span as? RichImageSpan {
                return RichImageSpan(alignment: image.alignment, baseline: image.baseline, style: widened(image.style))
            }
            guard let t = span as? TextSpan else { return span }
            return TextSpan(text: t.text, children: t.children.map { $0.map(copy) }, style: widened(t.style))
        }
        let strut = painter.strutStyle.map { s in
            StrutStyle(fontFamily: s.fontFamily, fontFamilyFallback: s.fontFamilyFallback,
                       fontSize: s.fontSize.map { $0 / k }, height: s.height.map { $0 * k },
                       leadingDistribution: s.leadingDistribution, fontWeight: s.fontWeight,
                       forceStrutHeight: s.forceStrutHeight)
        }
        let wide = TextPainter(text: copy(root), textAlign: painter.textAlign, textDirection: painter.textDirection ?? .ltr,
                               strutStyle: strut)
        wide.fractionalLineHeights = painter.fractionalLineHeights
        if let dims = painter.placeholderDimensions {
            wide.setPlaceholderDimensions(dims.map {
                PlaceholderDimensions(size: Size($0.size.width / k, $0.size.height), alignment: $0.alignment,
                                      baseline: $0.baseline, baselineOffset: $0.baselineOffset)
            })
        }
        wide.layout(minWidth: painter.width / k, maxWidth: painter.width / k)
        _widePainters[id] = (painter, wide)
        return wide
    }

    /// Word's geometry for a list paragraph, where the file gives it
    /// (points): the text's left, the first line's offset from it — the
    /// number stands there — and the level's format. nil for a list of
    /// the editor's own making, which keeps the theme's slot.
    func _wordList(_ p: RichParagraph, _ document: RichDocument) -> (left: Double, first: Double, format: ListLevelFormat?)? {
        guard theme.wordRules, p.style.list != nil, p.image == nil else { return nil }
        let f = p.style.listId.flatMap { document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)] }
        // (A level that states no indents leaves the paragraph's own:
        // zh-5901e2b0's "（二）" levels say none, the paragraphs indent
        // their first lines two characters, and Word sets the number
        // there with the text straight after it — in the editor's own
        // slot the number wrapped its "）" onto a line of its own.)
        // (Nor the paragraph a first line: the number at its left and the
        // text straight after it all the same — zh-9ba2ead7's table cells
        // number "1、" (suffix nothing, no indents anywhere) at the cell's
        // text edge in Word's print, where the editor's slot hung the
        // number 23pt out of it.)
        guard let left = p.style.listIndentLeft ?? f?.indentLeft ?? (f != nil ? p.style.indentLeft : nil)
        else { return nil }
        return (left, p.style.listFirstLine ?? -(f?.hanging ?? 0), f)
    }

    /// The first run's style as a Slides bullet takes it: its face, size
    /// and colour, never its lines or highlight — PowerPoint draws the
    /// "•" before an underlined run bare (Maloney's theory names).
    static func _slidesMarkerChar(_ run: CharStyle) -> CharStyle {
        var c = run
        c.underline = false
        c.strikethrough = false
        c.highlight = nil
        c.link = nil
        return c
    }

    /// A Slides marker as its paragraph draws it, laid out at its width.
    func _hangMarker(_ i: Int, _ p: RichParagraph, _ document: RichDocument, label: String) -> TextPainter {
        var markerChar = Self._slidesMarkerChar(p.runs.first?.style ?? CharStyle())
        if let c = p.style.bulletColor { markerChar.color = c }
        if let f = p.style.bulletStandInFamily ?? p.style.bulletFontFamily { markerChar.fontFamily = f }
        let k = (p.style.bulletScale ?? 1) * (p.style.bulletStandInScale ?? 1)
        if k != 1 { markerChar.fontSize = (markerChar.fontSize ?? _named(p, document)?.char.fontSize ?? theme.fontSize) * k }
        let style = theme.textStyle(for: markerChar, in: p.style, named: _named(p, document), normal: _normalChar(document), scale: scale, fontScale: fontScale)
        let marker = TextPainter(text: TextSpan(text: label, style: style), textAlign: .left, textDirection: .ltr)
        marker.layout(minWidth: 0, maxWidth: 100_000)
        return marker
    }

    /// The size, in points, a Word list level gives its number
    /// (`w:sz` in the level's run properties), if it says one.
    /// Whether a paragraph's boxes hold a larger list number's height
    /// above its first line (`_span`): a box of no picture that has a
    /// height, which a strut holding every line to the text's would
    /// undo.
    static func _risesForNumber(_ inline: [(image: ImageAttachment?, dimensions: PlaceholderDimensions)]) -> Bool {
        inline.contains { $0.image == nil && $0.dimensions.size.height > 0.5 }
    }

    /// The style of the word joiner that gives a line holding a CJK
    /// compatibility ideograph Noto Sans SC's line (`_span`): as much
    /// higher over the baseline and deeper under it than the line of
    /// `own` (the ideographs' style) as Word's Noto line is than that
    /// face's. The joiner's glyph is whatever face has it, and the engine
    /// shares a height out by that face's ascent and descent; at an even
    /// share its ascent less its descent is fixed by the size alone, so
    /// the size sets that and the height the rest. Nil where either
    /// face's baseline is not known, or the line's height is exact.
    /// A zero-width joiner whose line is Segoe UI Symbol's — its hhea
    /// ascent and descent, 2210 and 514 of 2048, at the run's size — in
    /// Noto Sans SC, a face that has the joiner (as `_notoJoiner`'s).
    func _segoeJoiner(_ run: CharStyle, _ named: RichNamedStyle?, _ own: TextStyle, _ paragraph: RichParagraphStyle,
                              _ pitch: Double?, _ scale: Double) -> TextStyle? {
        _lineJoiner(run, named, own, paragraph, pitch, scale, ascent: 2210.0 / 2048, descent: 514.0 / 2048, spacing: false)
    }

    /// The same joiner for a face of the given ascent and descent in ems (its hhea): the line a Devanagari word
    /// gives Word's line, Mangal's 1.241 + 0.438 (`_span`).
    func _lineJoiner(_ run: CharStyle, _ named: RichNamedStyle?, _ own: TextStyle, _ paragraph: RichParagraphStyle,
                     _ pitch: Double?, _ scale: Double, ascent ems: Double, descent emsDown: Double, spacing: Bool = true, belowOnly: Bool = false) -> TextStyle? {
        guard paragraph.lineHeightPoints == nil || paragraph.lineHeightIsMinimum, let px = own.fontSize, px > 0.5 else { return nil }
        var noto = run
        noto.eastAsiaFontFamily = "Noto Sans SC"
        let joinerStyle = theme.textStyle(for: noto, in: paragraph, named: named, normal: nil, scale: scale, fontScale: fontScale,
                                          eastAsian: true, gridPitch: pitch, scriptHidden: true)
        let probe = joinerStyle.copyWith(fontSize: 100, letterSpacing: 0, height: 1, leadingDistribution: .even)
        let t = TextPainter(text: TextSpan(text: "\u{2060}", style: probe), textDirection: .ltr)
        t.layout(minWidth: 0, maxWidth: 100_000)
        defer { t.dispose() }
        guard let line = t.computeLineMetrics().first else { return nil }
        let split = (line.ascent - line.descent) / 100
        // (A multiple of lines (Word's 1.15) takes this line too, as it does any other.)
        let multiple = spacing && paragraph.lineHeightPoints == nil && paragraph.lineSpacing > 0.5 ? paragraph.lineSpacing : 1
        let cut = belowOnly ? Self._multipleSplit(ascent: ems, descent: emsDown, multiple: multiple) : (ems * multiple, emsDown * multiple)
        // (A character scale (w:w) is laid out as a larger size; the line's height follows the authored size.)
        let own1 = RichTextTheme.wordWidthScale(run.horizontalScale ?? named?.char.horizontalScale ?? 1, wordRules: theme.wordRules,
            eastAsiaFamily: run.eastAsiaFontFamily ?? named?.char.eastAsiaFontFamily ?? run.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily)
        let pxLine = own1 > 0.01 ? px / own1 : px
        let ascent = pxLine * cut.0, descent = pxLine * cut.1
        guard split > 0.05 else { return nil }
        let size = (ascent - descent) / split
        return joinerStyle.copyWith(fontSize: size, letterSpacing: 0, height: (ascent + descent) / size, leadingDistribution: .even)
    }

    func _notoJoiner(_ noto: CharStyle, _ notoStyle: TextStyle, _ run: CharStyle, _ named: RichNamedStyle?, _ own: TextStyle,
                             _ paragraph: RichParagraphStyle, _ pitch: Double?, _ scale: Double) -> TextStyle? {
        guard paragraph.lineHeightPoints == nil || paragraph.lineHeightIsMinimum,
              let notoBase = theme.baseline(for: noto, in: paragraph, named: named, eastAsian: true, gridPitch: pitch),
              let ownBase = theme.baseline(for: run, in: paragraph, named: named, eastAsian: true, gridPitch: pitch),
              let nh = notoStyle.height, let ns = notoStyle.fontSize, let oh = own.height, let os = own.fontSize else { return nil }
        let k = theme.pixelsPerPoint * scale
        let rise = (notoBase - ownBase) * k
        let fall = (nh * ns - notoBase * k) - (oh * os - ownBase * k)
        guard rise > 0.01 || fall > 0.01 else { return nil }
        func metrics(_ text: String, _ style: TextStyle) -> (Double, Double)? {
            let t = TextPainter(text: TextSpan(text: text, style: style), textDirection: .ltr)
            t.layout(minWidth: 0, maxWidth: 100_000)
            defer { t.dispose() }
            return t.computeLineMetrics().first.map { ($0.ascent, $0.descent) }
        }
        let probe = notoStyle.copyWith(fontSize: 100, letterSpacing: 0, height: 1, leadingDistribution: .even)
        guard let line = metrics("\u{4E00}", own), let joiner = metrics("\u{2060}", probe) else { return nil }
        let ascent = line.0 + max(0, rise), descent = line.1 + max(0, fall)
        let split = (joiner.0 - joiner.1) / 100
        guard split > 0.05, ascent > descent else { return nil }
        let size = (ascent - descent) / split
        return notoStyle.copyWith(fontSize: size, letterSpacing: 0, height: (ascent + descent) / size, leadingDistribution: .even)
    }

    /// The paragraph mark's size: its own, else its paragraph style's —
    /// not the first run's (`_marker`).
    func _markSize(_ p: RichParagraph, _ document: RichDocument) -> Double? {
        p.style.mark?.fontSize ?? (p.style.mark == nil ? _named(p, document)?.char.fontSize ?? _normalChar(document)?.fontSize : nil)
    }

    /// The faces a list level names for its number (`w:rFonts` in its
    /// `w:rPr`): the Latin one and the East Asian one.
    func _levelNumberFonts(_ p: RichParagraph, _ document: RichDocument) -> (latin: String?, eastAsian: String?) {
        guard p.style.list != nil,
              let xml = p.style.listId.flatMap({ document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.numberRPrXML }) else { return (nil, nil) }
        func attr(_ name: String) -> String? {
            guard let r = xml.rangeOfSubstring(name + "=\"") else { return nil }
            return String(xml[r.upperBound...].prefix { $0 != "\"" })
        }
        // (A number of ASCII characters alone is set in the ASCII slot, which
        // a level naming only a high ANSI face leaves to the paragraph's:
        // zh-57f1de0d's "%1." under `w:hAnsi` "Arial Unicode MS" is NSimSun
        // like its text in Word's print, 11.04 wide; ours drew Liberation Sans'
        // 9.2 and its taller line made every numbered row 3pt too deep. A
        // bullet is no ASCII, and keeps the high ANSI face.)
        let level = p.style.listId.flatMap { document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)] }
        let asciiLabel = level.map { $0.format != .bullet && !$0.text.isEmpty && $0.text.unicodeScalars.allSatisfy { $0.isASCII } } ?? false
        if theme.wordRules, asciiLabel, attr("w:ascii") == nil, attr("w:hAnsi") != nil {
            RuleTrace.hit("level-hansi-only-ascii-label")
            return (nil, attr("w:eastAsia"))
        }
        return (attr("w:ascii") ?? attr("w:hAnsi"), attr("w:eastAsia"))
    }

    func _levelNumberSize(_ p: RichParagraph, _ document: RichDocument) -> Double? {
        guard p.style.list != nil,
              let xml = p.style.listId.flatMap({ document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.numberRPrXML }),
              let r = xml.rangeOfSubstring("<w:sz w:val=\"") else { return nil }
        return Double(xml[r.upperBound...].prefix { $0 != "\"" }).map { $0 / 2 }
    }

    /// Wingdings' advances, in ems, for the bullets the reader draws with
    /// stand-ins (`Docx`'s bullet map), as Word's prints embed them: "Ø"
    /// (zh-3fe252ff, zh-0d036e4e), "§" (Numbering), "l" (bug69628,
    /// zh-15428325).
    static let _wingdingsAdvances: [UInt32: Double] = [0xF0D8: 0.794, 0xF0A7: 0.458, 0xF06C: 0.747, 0xF06E: 0.747, 0xF075: 0.986, 0xF0A8: 0.891, 0xF06F: 0.891, 0xF09E: 0.313]

    /// Cambria Math's advances (ems, its hmtx) for the symbols Word for
    /// Windows sets in it where they open a stretch of what an embedded
    /// subset lacks (`_span`).
    static let _cambriaMathOpeners: [UInt32: Double] = {
        var out: [UInt32: Double] = [0x3014: 0.3501, 0x3015: 0.3501]
        for u in UInt32(0x2460) ... 0x2473 { out[u] = 1.2007 }
        return out
    }()

    /// Cambria Math's advances (ems) for the relations Cambria lacks (`_span`).
    static let _cambriaMathOpeners2: [UInt32: Double] = [0x2266: 0.7471, 0x2267: 0.7471]

    /// A list paragraph's marker, laid out at its own width.
    /// The character style a list label is set in (`_marker`).
    func _markerChar(_ p: RichParagraph, _ document: RichDocument) -> CharStyle {
        var markerChar = p.runs[0].style
        // (In the paragraph mark's formatting where the file gives the
        // mark any, not the text's, and underlined only where its level
        // says so: zh-9c5d0c3f's "四、" is 18pt as its mark over 16pt
        // text in Word's print, and none of its headings' numbers
        // carries the underline their marks and text have — nor
        // zh-90e0cea8's "12.", its mark underlined.)
        if theme.wordRules, p.style.list != nil {
            // (A mark the file gives no formatting of its own is the
            // paragraph style's, not the first run's: zh-117cf7c6's "※"
            // over 12pt text is Normal's 14pt in Word's print, and its
            // line 2.5pt taller than ours, every line after it lower.)
            markerChar = p.style.mark ?? CharStyle()
            // (In the faces its level names: zh-117cf7c6's "※" is the
            // level's 標楷體 — YaHei to Word — over Normal's Times.)
            // (Not a symbol face's: its bullets are drawn as their own.)
            let fonts = _levelNumberFonts(p, document)
            let symbolFaces: Set<String> = ["symbol", "wingdings", "wingdings 2", "wingdings 3", "webdings"]
            if let f = fonts.latin, !symbolFaces.contains(f.lowercased()) {
                markerChar.fontFamily = f
                if let e = fonts.eastAsian { markerChar.eastAsiaFontFamily = e }
            }
            let xml = p.style.listId.flatMap { document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.numberRPrXML } ?? ""
            markerChar.underline = xml.containsSubstring("<w:u ") && !xml.containsSubstring("<w:u w:val=\"none\"")
            // (A level whose run properties carry a `w14:scene3d` prints no number
            // at all in Word for Windows — lab `lvl3label`, one w14 element at a
            // time: glow, shadow, reflection, textOutline, props3d, ligatures
            // show it, scene3d alone hides it, vanish or not; the text stays at
            // the hanging indent. lo-5b9540e9's "4.2.1" headings.)
            let suffix = p.style.listId.flatMap { document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.suffix }
            // (Not where the level follows its number with nothing: zh-604e21e5,
            // zh-457a8d62 and zh-9db183d5 carry the same scene3d and print "(一)".)
            if xml.containsSubstring("<w14:scene3d"), suffix != "nothing" { markerChar.hidden = true }
            // (And spaced as its level says: zh-90e0cea8's annex headings
            // number "附录%1" under `<w:spacing w:val="100"/>`, "附 录 A"
            // in Word's print, 5pt after each character.)
            if let r = xml.rangeOfSubstring("<w:spacing w:val=\""), let v = Double(xml[r.upperBound...].prefix { $0 != "\"" }) {
                markerChar.letterSpacing = v / 20
            }
        }
        if let c = p.style.bulletColor { markerChar.color = c }
        // (The level's own size, where it says one: bug65649's "3.1.1."
        // is 14pt over 12pt text in Word's print.)
        if theme.wordRules, let size = _levelNumberSize(p, document) { markerChar.fontSize = size }
        if let k = p.style.bulletScale {
            markerChar.fontSize = (markerChar.fontSize ?? _named(p, document)?.char.fontSize ?? theme.fontSize) * k
        }
        return markerChar
    }

    func _marker(_ i: Int, _ p: RichParagraph, _ document: RichDocument, label: String, strut: StrutStyle?) -> TextPainter {
        let markerChar = _markerChar(p, document)
        let pitch = _offGrid(i, document) ? nil : _grid(i, document).pitch
        var named = _named(p, document)
        if theme.wordRules, p.text.isEmpty, markerChar.off.contains(.hidden) { named?.char.hidden = false }
        // East Asian numbers in the run's East Asian face, as the text.
        let ea = theme.wordRules && label.contains(where: { Self.isEastAsian($0, hinted: true) })
        var markerStyle = theme.textStyle(for: markerChar, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, eastAsian: ea, gridPitch: pitch)
        // (A square or circle label in an East Asian face is that face's glyph, an em
        // wide: zh-bdae17c0's "□" in 標楷體 is DFKai-SB's, 14pt in Word's print, where
        // the Latin stand-in's fallback drew Liberation Mono's at 11.7.)
        if theme.wordRules, ea, label.count == 1, let u = label.unicodeScalars.first?.value, (0x25A0 ... 0x25EF).contains(u),
           let cjk = Self._cjkFaceFamily {
            RuleTrace.hit("word-east-asian-geometric-label-is-the-cjk-faces-glyph")
            markerStyle = markerStyle.copyWith(fontFamily: cjk)
        }
        // (Its full-width characters spaced twice where single and double
        // byte widths are balanced, as the text's are: zh-90e0cea8's
        // "附 录 A", spaced 5pt, steps 20.5 at 10.5pt and its "A" 5.)
        if theme.wordRules, ea, document.balancesSpaceWidth, let ls = markerChar.letterSpacing, ls != 0 {
            markerStyle = markerStyle.copyWith(letterSpacing: (markerStyle.letterSpacing ?? 0) + ls * theme.pixelsPerPoint * scale)
        }
        // A Wingdings bullet, drawn by a stand-in glyph, takes Wingdings'
        // own advance: its "Ø" arrowhead is 0.794 of an em in Word's
        // prints (their embedded subsets' widths), and zh-3fe252ff's
        // 15pt one ends at 41.9pt from a 30pt first-line indent, short of
        // the 42pt default stop where Word starts the text; the "➢" drawn
        // for it ran past, and the text went on to 63 — every bullet's
        // line held two characters fewer, and from p23 on its pages ran a
        // line late.
        if theme.wordRules, label.count == 1, let ch = label.first, _levelNumberFonts(p, document).latin?.lowercased() == "wingdings",
           let raw = p.style.listId.flatMap({ document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.rawText })?.unicodeScalars.first?.value,
           let em = Self._wingdingsAdvances[raw] {
            // (Of the size the file gives, not the stand-in face's scaled
            // one: the text's 仿宋_GB2312 sets the marker at 16.05pt here.)
            let size = _px(markerChar.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize) * fontScale
            markerStyle = markerStyle.copyWith(letterSpacing: (markerStyle.letterSpacing ?? 0) + em * size - _glyphWidth(markerStyle, ch))
        }
        // Its Latin characters in the Latin face all the same — the
        // number's own (its level's `w:rFonts`, else the paragraph
        // mark's), whatever the hint: the "1" of zh-06c46ba9's "（1）" is
        // Times New Roman's 7pt in Word's print, and the parens of
        // zh-4b8e0abc's "(一)", hinted East Asian, are Cambria's 0.382
        // em (the paragraph's majorHAnsi), 24.7pt in all, so the number
        // overflows its 24.1pt hanging indent and the text goes to the
        // next default stop; drawn from the East Asian style's base
        // family they were 0.333 em, the number fit, and the text
        // started 9pt early. An ascii face that is itself East Asian
        // (zh-90e0cea8's 黑体) resolves to that face's own Latin.
        func latinChar(_ c: Character) -> Bool {
            if theme.wordRules, ea, Self._cjkFaceFamily != nil, let u = c.unicodeScalars.first?.value, (0x25A0 ... 0x25EF).contains(u) { return false }
            return !Self.isEastAsian(c, hinted: false)
        }
        // (… and a number of Latin characters alone too: zh-12c4f07a's
        // "3.3.1.1." in its level's 14pt 標楷體 is YaHei's 0.586 em a digit
        // and 0.241 a stop in Word's print, ending under the 96pt default
        // stop, where the stand-in's own widths ran it 3.7pt past and the
        // text went on to the indent, a character a line fewer.)
        let latinStyle = theme.wordRules && label.contains(where: latinChar)
            ? (ea ? theme.textStyle(for: markerChar, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale, eastAsian: false, gridPitch: pitch)
                : markerStyle)
            : nil
        // (At the face's own advances, as the text's spans are set: the
        // stand-in's glyph widened or narrowed to the width the face
        // gives the character.)
        let latinFace = latinStyle != nil ? theme.faceResolver?(markerChar.fontFamily ?? named?.char.fontFamily ?? _normalChar(document)?.fontFamily ?? theme.fontFamily, false) : nil
        func advanced(_ ch: Character, _ st: TextStyle) -> TextStyle {
            guard let face = latinFace, let table = face.advanceTable(bold: st.fontWeight == .bold, italic: st.fontStyle == .italic),
                  let u = ch.unicodeScalars.first?.value, ch.unicodeScalars.count == 1, u >= 0x20, u <= 0x7E,
                  Int(u) - 0x20 < table.count, let px = st.fontSize, px > 0.5 else { return st }
            let extra = table[Int(u) - 0x20] * px / face.sizeScale - _glyphWidth(st, ch)
            return st.copyWith(letterSpacing: (st.letterSpacing ?? 0) + extra)
        }
        // The number is on the document's character grid like the text
        // after it — each character wider by the grid's addition, a
        // half-width one by half of it where widths are balanced: Word
        // sets "（2）" 43.97pt wide at 16pt on a grid of 1.008, and the
        // text begins there (zh-457a8d62; it was 41.4 here, and the
        // line took a character more).
        var span = latinStyle.map { latin in
            TextSpan(children: label.map { TextSpan(text: String($0), style: latinChar($0) ? advanced($0, latin) : markerStyle) })
        } ?? TextSpan(text: label, style: markerStyle)
        // (Unless the mark is off it — and not then where the level
        // puts its number on it: zh-c15af02e's heading 6 level says
        // `<w:snapToGrid/>` over runs off a grid of 1pt, and Word sets
        // "〈2〉" 17.0, 9.9 and 17.0 at 16pt, the line a character short of
        // ours.)
        let levelGrid = p.style.listId.flatMap { document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.numberRPrXML }
            .flatMap { xml -> Bool? in
                guard let r = xml.rangeOfSubstring("<w:snapToGrid") else { return nil }
                let tag = xml[r.upperBound...].prefix(while: { $0 != ">" })
                return !(tag.containsSubstring("w:val=\"0\"") || tag.containsSubstring("w:val=\"false\"") || tag.containsSubstring("w:val=\"off\""))
            }
        if theme.wordRules, let g = _grid(i, document).chars, g != 0,
           levelGrid ?? !(markerChar.keptXML?.containsSubstring("<w:snapToGrid w:val=\"0\"") ?? false),
           p.style.eastAsian["w:snapToGrid"] != "0" {
            func spaced(_ st: TextStyle, _ by: Double) -> TextStyle { st.copyWith(letterSpacing: (st.letterSpacing ?? 0) + by) }
            let latin = latinStyle ?? markerStyle
            span = TextSpan(children: label.map { ch in
                !latinChar(ch)
                    ? TextSpan(text: String(ch), style: spaced(markerStyle, _px(g)))
                    : TextSpan(text: String(ch), style: spaced(advanced(ch, latin), document.balancesSpaceWidth ? _px(g) / 2 : _px(g)))
            })
        }
        // (At its level's character scale, each character's advance that
        // much of its own, the spacing after it not: zh-7773163d's
        // "（%1）" level says `<w:w w:val="94"/>` and 0.9pt spacing at
        // 18pt, and Word's "（3）" ends at 160.8, under the stop at 161.9
        // where the text begins; at full width ours ended at 163.7, the
        // text went on to the next stop, and each item's first line held
        // two characters fewer.)
        if theme.wordRules, let xml = p.style.listId.flatMap({ document.listFormats[$0]?[min(max(0, p.style.listLevel), 8)]?.numberRPrXML }),
           let r = xml.rangeOfSubstring("<w:w w:val=\""), let v = Double(xml[r.upperBound...].prefix { $0 != "\"" }), v > 0, abs(v - 100) > 0.5 {
            let k = v / 100
            func narrowed(_ span: InlineSpan, _ inherited: TextStyle?) -> InlineSpan {
                guard let t = span as? TextSpan else { return span }
                let style = t.style.map { inherited?.merge($0) ?? $0 } ?? inherited
                if let text = t.text, !text.isEmpty, let st = style {
                    return TextSpan(children: text.map { ch in
                        TextSpan(text: String(ch), style: st.copyWith(letterSpacing: (st.letterSpacing ?? 0) - (1 - k) * _glyphWidth(st.copyWith(letterSpacing: 0), ch)))
                    } + (t.children ?? []).map { narrowed($0, style) })
                }
                guard let kids = t.children else { return span }
                return TextSpan(text: t.text, children: kids.map { narrowed($0, style) }, style: t.style)
            }
            span = narrowed(span, nil) as? TextSpan ?? span
        }
        // (A spacing that takes a character back past its own start takes
        // it back to it: zh-7773163d's "（%2）" level is spaced -17.3pt at
        // 17pt, and Word's print stacks "（", "1" and "）" at the indent;
        // the engine drew none of a label narrower than nothing, and the
        // matcher found none of its lines.)
        if theme.wordRules {
            func clamped(_ span: InlineSpan, _ inherited: TextStyle?) -> InlineSpan {
                guard let t = span as? TextSpan else { return span }
                let style = t.style.map { inherited?.merge($0) ?? $0 } ?? inherited
                if let text = t.text, !text.isEmpty, let st = style, let ls = st.letterSpacing, ls < 0,
                   text.contains(where: { ls < -_glyphWidth(st.copyWith(letterSpacing: 0), $0) }) {
                    return TextSpan(children: text.map { ch in
                        TextSpan(text: String(ch), style: st.copyWith(letterSpacing: max(ls, -_glyphWidth(st.copyWith(letterSpacing: 0), ch))))
                    })
                }
                guard let kids = t.children else { return span }
                return TextSpan(text: t.text, children: kids.map { clamped($0, style) }, style: t.style)
            }
            span = clamped(span, nil) as? TextSpan ?? span
        }
        let marker = TextPainter(text: span, textAlign: .left, textDirection: .ltr, strutStyle: strut)
        marker.layout(minWidth: 0, maxWidth: 100_000)
        return marker
    }

    /// Whether two punctuation marks that stand together close up in
    /// this run: by the East Asian rules, where the text kerns
    /// (`w:kern`, from that size up) and the document's punctuation may.
    func _closesUpMarks(_ run: CharStyle, _ named: RichNamedStyle?, _ document: RichDocument) -> Bool {
        guard theme.wordRules, document.usesEastAsianLayout, document.kernsPunctuation,
              let from = run.kerningFrom ?? named?.char.kerningFrom ?? _normalChar(document)?.kerningFrom, from > 0 else { return false }
        return (run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize) >= from
    }

    /// What to take off which characters (paragraph offset → pixels,
    /// negative) so that the engine breaks this paragraph's lines where
    /// Word does: see `_layoutParagraph`. The paragraph is laid out once
    /// more at no width, which makes a line of every stretch the engine
    /// will not break — the break opportunities and the widths between
    /// them, by the engine's own measure — and Word's rules are run over
    /// those. Measured from Word 16's prints, 2026-10-12, and only in a
    /// justified paragraph: a closing mark
    /// hangs unless the paragraph says `w:overflowPunct` off; a line
    /// gives up to half an em, off its punctuation, where the document's
    /// `w:characterSpacingControl` compresses punctuation.
    ///
    /// The automatic space between an ideograph and a letter or digit
    /// (see `_span`) is between two characters of a line: after a
    /// line's last character there is none, in any paragraph (a line of
    /// 25 ideographs and "C" is taken at 414.7pt, the letter's own
    /// 10.7 and the 4 before it, not the 4 after). And where punctuation
    /// is compressed, before Word 2013's layout, each such space on the
    /// line gives up to half of itself like a mark does: one "C" among
    /// twenty ideographs takes the next one 4pt over, two take it 8 —
    /// the half em that is the most a line takes — and the space before
    /// a last "C" 2 (measured 2026-10-12; with `doNotCompress` none
    /// gives). From 2013's layout on they give in a justified paragraph
    /// only and by another rule, not found: one space gave 4pt, two
    /// under 4, four under 5.
    ///
    /// In a table's cell no mark hangs; the marks inside a line give
    /// there as anywhere.
    /// The offsets `_span` keeps Thai together at (word joiners): see there.
    func _thaiJoins(_ p: RichParagraph, _ document: RichDocument, named: RichNamedStyle?, textWidth: Double, lead: Double) -> Set<Int> {
        var thaiJoins: Set<Int> = []
        if theme.wordRules, RichTextTheme.thaiBreaksAtSpaces, p.text.unicodeScalars.contains(where: { (0x0E01 ... 0x0E5B).contains($0.value) }) {
            let units = Array(p.text.utf16)
            let em = (p.runs.first?.style.fontSize ?? named?.char.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
            var k = 0
            while k < units.count {
                guard units[k] != 0x20, units[k] != 0x3000, units[k] != 0x0A else { k += 1; continue }
                var end = k, thai = false, width = 0.0
                while end < units.count, units[end] != 0x20, units[end] != 0x3000, units[end] != 0x0A {
                    let u = units[end]
                    if (0x0E01 ... 0x0E5B).contains(u) {
                        thai = true
                        width += [0x0E31, 0x0E34, 0x0E35, 0x0E36, 0x0E37, 0x0E38, 0x0E39, 0x0E3A, 0x0E47, 0x0E48, 0x0E49, 0x0E4A, 0x0E4B, 0x0E4C, 0x0E4D, 0x0E4E].contains(u) ? 0 : 0.42 * em
                    } else { width += 0.5 * em }
                    end += 1
                }
                // (The first stretch against the first line's room, after
                // its indent and number: that one is where it would stand.)
                let room = k == 0 ? textWidth - max(0, lead) : textWidth
                if thai, width <= room || k > 0 { for o in (k + 1) ..< max(k + 1, end) { thaiJoins.insert(o) } }
                // (A stretch wider than a whole line is broken where the line fills, at any letter's start, as Word's print of
                // xd 0815aa59 ends "…ปั" and starts "ตตานี…" — no dictionary word edge there. Break chances are marked as -offset.)
                else if thai, width > textWidth {
                    for o in (k + 1) ..< max(k + 1, end) {
                        let c = units[o], b = units[o - 1]
                        if ((0x0E01 ... 0x0E2E).contains(c) || (0x0E40 ... 0x0E44).contains(c)), !(0x0E40 ... 0x0E44).contains(b) { thaiJoins.insert(-o) }
                    }
                }
                k = end
            }
        }
        return thaiJoins
    }

    /// How many full-width characters of the paragraph's first run fit one line.
    func _hanFitChars(_ p: RichParagraph, named: RichNamedStyle?, textWidth: Double) -> Int {
        let em = (p.runs.first?.style.fontSize ?? named?.char.fontSize ?? theme.fontSize) * theme.pixelsPerPoint * scale
        return em > 0 ? Int(textWidth / em) : Int.max
    }

    /// `RichDocument.joinsHanAfterSpace`: the offsets (UTF-16) inside each
    /// stretch after a space, to the next space or tab, that holds Han
    /// text — kept together, the engine breaking one longer than a line
    /// where it fills. Empty where the document does not say so.
    static func _hanJoins(_ p: RichParagraph, _ document: RichDocument, index: Int? = nil, fitChars: Int = Int.max) -> Set<Int> {
        guard RichTextTheme.wordWindowsPages else { return [] }
        let fitJoined = _fitTextJoins(p, index, document)
        guard document.joinsHanAfterSpace else { return fitJoined }
        let units = Array(p.text.utf16)
        func blank(_ u: UInt16) -> Bool { u == 0x20 || u == 0x3000 }
        var joins: Set<Int> = []
        var k = 0
        while k < units.count {
            guard units[k] == 0x20 || units[k] == 0x3000 else { k += 1; continue }
            var start = k + 1
            while start < units.count, units[start] == 0x20 || units[start] == 0x3000 { start += 1 }
            var end = start, han = false, kana = false
            while end < units.count, !blank(units[end]) {
                if (0x3400 ... 0x9FFF).contains(units[end]) || (0xF900 ... 0xFAFF).contains(units[end]) { han = true }
                if (0x3040 ... 0x30FF).contains(units[end]) { kana = true }
                end += 1
            }
            // (Not Japanese: jpn-z23845932 (Pandoc, mode none, theme face), "(a) 出版頻度の制約。 Amazon
            // KDPをはじめ…" in Word's print breaks inside the kana-bearing stretch, every line full.)
            // (A kana-bearing stretch that fits a line (fitChars full-width characters) stays one
            // word, as jpn-z17607492's "典型的な距離:畑から…マイル" does in Word's print: the line
            // breaks before it, not inside.)
            // (Compat 12, lab compat12 and dx2 f8ff8a48: Word keeps a stretch whole only when it is wider than a line;
            // "图表同屏https://…/download" (about 19 em, fits) breaks at the Han/Latin edge, Han 1 em, other 0.5 em.)
            if document.compatibilityMode == 12, han {
                var em2 = 0
                for o in start ..< end { em2 += (0x2E80 ... 0xFFEF).contains(units[o]) ? 2 : 1 }
                if em2 <= 2 * fitChars { k = max(end, start); continue }
            }
            if han, !kana || end - start <= fitChars { for o in (start + 1) ..< max(start + 1, end) { joins.insert(o) } }
            k = max(end, start)
        }
        return joins.union(fitJoined)
    }

    /// A paragraph in a cell with `w:tcFitText`: Word spreads its letters over the cell's room (spacing in whole 96-dpi pixels,
    /// see `_tcFitMarginSlack`; labs fit1, mar1, mar2, tcfit*). Lab fit1 matches Word on 4 of 6 margins; margin 28 at 12 pt and
    /// margin 150 at 20 pt are one pixel step off (open).
    static let _tcFitEnabled = true
    @inline(never) static func _tcFitParagraph(_ p: RichParagraph, _ index: Int?, _ document: RichDocument) -> Bool {
        guard Self._tcFitEnabled, let cell = p.cell, cell.keptPropertiesXML?.containsSubstring("w:tcFitText") == true else { return false }
        return true
    }

    /// Word's fit text in a cell works in 96-dpi screen pixels: each side's cell margin (tcMar, else tblCellMar, else 5.4 pt) is
    /// rounded UP to a whole pixel (labs fit1, mar1, mar2). Returns, in points, how much the room GROWS (negative: shrinks) against
    /// the cell's text width, which already has the exact margins taken off.
    @inline(never) static func _tcFitMarginSlack(_ p: RichParagraph, _ document: RichDocument) -> Double {
        let ts = p.cell.flatMap { document.tableStyles[$0.table] }
        let l = p.cell?.padding?.left ?? ts?.cellMarginLeft ?? 5.4, r = p.cell?.padding?.right ?? ts?.cellMarginRight ?? 5.4
        func up(_ v: Double) -> Double { (v / 0.75 - 1e-6).rounded(.up) * 0.75 }
        return (l + r) - up(l) - up(r)
    }

    /// The offsets inside a `w:fitText` group (consecutive runs of one id): Word
    /// does not part a fitted group (9ba34429's "1学年" cell, 17.95pt of room for
    /// a group fitted to 18pt, stays one line in Word's print; ours wrapped the 年).
    @inline(never) static func _fitTextJoins(_ p: RichParagraph, _ index: Int?, _ document: RichDocument) -> Set<Int> {
        var joins: Set<Int> = []
        // (A cell with `w:tcFitText` fits its whole paragraph to the cell: one line, never parted; lab tcfit1, dx2 28dd0ac0.)
        // (Word DOES part a first fit cell's line: lab tcfit11/12 wrap 대비 alone at every width, so no join there.)
        if _tcFitParagraph(p, index, document) { return joins }
        var at = 0
        var previousId: String? = nil
        for r in p.runs {
            let id = _fitText(r.style.keptXML)?.id
            if let id, r.length > 0 {
                let from = id == previousId ? at : at + 1
                if from < at + r.length { for o in from ..< (at + r.length) { joins.insert(o) } }
            }
            if r.length > 0 { previousId = id }
            at += r.length
        }
        return joins
    }

    /// Whether a right-to-left paragraph's spaces give as a left-to-right one's
    /// (a quarter of themselves for a word that is over): Arabic script, with no
    /// Hebrew in it — lo tdf163575's Persian lines take a word more in Word's
    /// print on them (64.5 -> 83.9), while tdf129659's Hebrew, with its hyphen
    /// breaks, lost a line it had (100 -> 80) when the same fit was run over it.
    static func _squeezesRightToLeft(_ text: String) -> Bool {
        var arabic = false
        for u in text.unicodeScalars {
            if (0x0590 ... 0x05FF).contains(u.value) { return false }
            if (0x0600 ... 0x06FF).contains(u.value) { arabic = true }
        }
        return arabic
    }
}

extension RichLayout {
    /// Word (a file naming no compatibility mode; lab jwrap) starts a long space- or "——"-delimited
    /// piece on a fresh line when it does not fit the rest of the current one, then breaks inside it
    /// as usual (kinsoku). Found from the first layout, with its real widths and indents: a piece that
    /// starts mid-line and is cut by a line start inside it gets its first line's worth (the length
    /// of the line that starts at the cut) joined, so the engine moves that chunk whole.
    @inline(never)
    func _hanPieceMoves(_ i: Int, _ p: RichParagraph, _ document: RichDocument) {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, document.joinsHanAfterSpace, !p.text.isEmpty else { return }
        for _ in 0 ..< 40 {
            guard let painter = _painters[i], i < _inserts.count else { return }
            let units = Array(p.text.utf16)
            let starts = _lineStarts(painter, _OffsetMap(lead: _lead(i), inserts: _inserts[i]), count: units.count)
            guard starts.count > 1 else { return }
            let startSet = Set(starts)
            func blank(_ u: UInt16) -> Bool { u == 0x20 || u == 0x3000 || u == 0x0A || u == 0x09 }
            func dash(_ k: Int) -> Bool { k >= 1 && units[k] == 0x2014 && units[k - 1] == 0x2014 }
            // A Latin hyphen between two ASCII letters ("knife-edge") is a break of its own: Word breaks there and treats what follows as a new piece.
            func hyph(_ k: Int) -> Bool { k >= 1 && k + 1 < units.count && units[k] == 0x2D && units[k - 1] < 0x80 && units[k - 1] != 0x20 && units[k + 1] < 0x80 && units[k + 1] != 0x20 }
            var add = Set<Int>()
            var k = 1
            while k < units.count {
                // a piece starts after blanks or after a doubled dash
                guard blank(units[k - 1]) || dash(k - 1) || hyph(k - 1) else { k += 1; continue }
                var a = k
                while a < units.count, blank(units[a]) { a += 1 }
                var end = a, han = false
                while end < units.count, !blank(units[end]) {
                    if end > a, dash(end) { end += 1; break }
                    if end > a, hyph(end) { end += 1; break }
                    if (0x3040 ... 0x30FF).contains(units[end]) || (0x3400 ... 0x9FFF).contains(units[end]) { han = true }
                    end += 1
                }
                // (Compat 12, dx2 f8ff8a48: a piece that fits one of the paragraph's lines stays as laid out; see `_hanJoins`.)
                var fitsALine = false
                if han, document.compatibilityMode == 12 {
                    func em2(_ x: Int, _ y: Int) -> Int { units[x ..< y].reduce(0) { $0 + ((0x2E80 ... 0xFFEF).contains($1) ? 2 : 1) } }
                    var room = 0
                    for (n, st) in starts.enumerated() where n + 1 < starts.count { room = max(room, em2(st, starts[n + 1])) }
                    fitsALine = em2(a, end) <= room
                }
                if han, !fitsALine, a > 0, !startSet.contains(a), starts.contains(where: { $0 > a && $0 < end && !dash($0) }) {
                    if !(_hanChunks[i] ?? []).contains(a) { add.insert(a); break }
                }
                k = max(end, k + 1)
            }
            let have = _hanChunks[i] ?? []
            if add.isSubset(of: have) { return }
            _hanChunks[i] = have.union(add)
            _layoutParagraphOnce(i, p, document)
        }
    }
}
