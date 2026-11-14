// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Equations in Writer: a .docx's Office Math (`m:oMath`, and a display
// equation's `m:oMathPara`) is kept as an object, written back as the file
// had it, and drawn here through `RichLayout.objectPainter`, laid out as a
// small tree of boxes — runs, scripts, n-ary operators with their limits,
// fractions, delimiters, radicals, functions, accents, bars, limits,
// arrays and matrices; anything else is its children in a row. Without
// this an equation was gone from the page and from a save: zh-20ff844e's
// two scoring formulas, and the 50pt they stand in.

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

enum WriterMath {
    /// A laid-out piece of an equation, in points: its width, how far it
    /// reaches above and below its baseline, and how to draw it with its
    /// baseline's left end at a point.
    struct Box {
        var width: Double
        var ascent: Double
        var descent: Double
        /// How far its ink reaches (nil: as far as its line extents), to size a stretched delimiter.
        var inkUp: Double? = nil
        var inkDown: Double? = nil
        var draw: (any Canvas, Offset) -> Void
        var iu: Double { inkUp ?? ascent }
        var idn: Double { inkDown ?? descent }
        static let empty = Box(width: 0, ascent: 0, descent: 0) { _, _ in }
    }

    private struct Entry {
        let box: Box
        /// What it was laid out from, to lay it out again narrower.
        var node: XNode? = nil
        var size: Double = 11
        /// Its forms broken to a width (`fit`).
        var fits: [Box] = []
    }

    /// An inline equation cut after each relation of its top level (Word breaks one there, and nowhere
    /// else: jpn-z22855378-6fca0f's "重心座標 X=" ends a line, its fraction begins the next). The pieces
    /// are drawn side by side as the whole was; every piece after the first carries `cont`, so a sign
    /// that opens it keeps its gaps as after a relation.
    static func splitAtRelations(_ node: XNode) -> [XNode] {
        let relations: Set<Character> = ["=", "<", ">", "≤", "≥", "≈", "≠"]
        var pieces: [[XNode]] = [[]]
        for (i, c) in node.children.enumerated() {
            guard c.name == "m:r", c.all("m:t").count == 1, let t = c.first("m:t") else { pieces[pieces.count - 1].append(c); continue }
            var cur = ""
            var parts: [String] = []
            for ch in t.text { cur.append(ch); if relations.contains(ch) { parts.append(cur); cur = "" } }
            if !cur.isEmpty { parts.append(cur) }
            func part(_ text: String) -> XNode {
                let r = XNode(name: c.name, attrs: c.attrs)
                for k in c.children {
                    if k === t { let n = XNode(name: k.name, attrs: k.attrs); n.text = text; r.children.append(n) } else { r.children.append(k) }
                }
                return r
            }
            for (k, text) in parts.enumerated() {
                pieces[pieces.count - 1].append(parts.count == 1 ? c : part(text))
                let endsRelation = text.last.map { relations.contains($0) } ?? false
                let more = k < parts.count - 1 || node.children[(i + 1)...].contains { !$0.name.hasSuffix("Pr") }
                if endsRelation, more { pieces.append([]) }
            }
        }
        guard pieces.count > 1 else { return [node] }
        return pieces.enumerated().map { k, kids in
            let n = XNode(name: node.name, attrs: node.attrs)
            if k > 0 { n.attrs["cont"] = "1" }
            n.children = kids
            return n
        }
    }

    private nonisolated(unsafe) static var entries: [String: Entry] = [:]
    private static let lock = RegistryLock()

    /// Lays out the equation `node` (`m:oMath` or `m:oMathPara`) for the
    /// object attachment `id`, its text `size` points where its runs say
    /// none; its size and baseline (from its top), in points.
    static func register(_ node: XNode, for id: String, size: Double, natural: ((Double, Double)) -> Void = { _ in }) -> (width: Double, height: Double, baseline: Double)? {
        let display = node.name == "m:oMathPara"
        var box = Layout(display: display, inlineText: !display).row(node, size: size, level: 0)
        guard box.width > 0 else { return nil }
        // (An equation in a line takes no more of it than its text would:
        // its scripts reach into the line's leading, as Word sets them —
        // zh-c2c92639's "式中：C_dm ——…" lines are one 16.65pt pitch of its
        // grid in Word's print, where the subscript's depth took ours two.
        // It is drawn whole all the same.)
        natural((box.ascent, box.descent))
        // (A display equation ending on a manual break, `<w:br/>` in its last
        // run, is one empty line longer: Word sets that line under it, 7f0539's
        // equations stand a line apart from the text after them; 158454's
        // taller ones the same single line, not their own height again.)
        if display, node.all("m:oMath").last?.children.last(where: { $0.name == "m:r" })?.first("w:br") != nil {
            box.descent += size * 1.172   // a plain line of the equation font, as Word sets the empty one
        }
        if !display {
            let s = Layout(display: false).runSize(node, size)
            box.ascent = min(box.ascent, s * 0.85)
            box.descent = min(box.descent, s * 0.22)
        }
        lock.lock()
        entries[id] = Entry(box: box, node: display ? node : nil, size: size)
        lock.unlock()
        WriterCharts.installHooks()
        return (box.width, box.ascent + box.descent, box.ascent)
    }

    /// The display equation registered for `attachment` laid out again,
    /// broken over lines to `width` points, where it is wider: its size
    /// and first baseline, in points. nil where it fits, or cannot part.
    /// Word parts a display equation too wide for its line before an
    /// operator — inside the brackets of one round it all as well — and
    /// sets each line after the first an inch in (`m:wrapIndent`'s
    /// default): zh-db07d44e's cell "實績值=(…/…×1/3+…/…×1/3+…/…×1/3)×100%"
    /// is four lines in its print, the last "×100%".
    static func fit(_ attachment: ImageAttachment, width: Double) -> (width: Double, height: Double, baseline: Double)? {
        lock.lock()
        let entry = entries[attachment.id]
        lock.unlock()
        guard let entry, let node = entry.node, entry.box.width > width + 0.5 else { return nil }
        let layout = Layout(display: true)
        let pieces = layout.pieces(node, size: entry.size)
        guard pieces.count > 1 else { return nil }
        let indent = min(72, width / 2)
        var lines: [[Box]] = [[]]
        var x = 0.0
        for (k, piece) in pieces.enumerated() {
            let limit = lines.count == 1 ? width : width - indent
            if k > 0, piece.breaksBefore, !lines[lines.count - 1].isEmpty {
                // (Where what runs on to the next break would not fit.)
                var run = piece.box.width
                var j = k + 1
                while j < pieces.count, !pieces[j].breaksBefore { run += pieces[j].box.width; j += 1 }
                if x + run > limit + 0.01 { lines.append([]); x = 0 }
            }
            lines[lines.count - 1].append(piece.box)
            x += piece.box.width
        }
        guard lines.count > 1 else { return nil }
        let boxes = lines.map { layout.hbox($0) }
        // (0.3 of its size between lines: zh-db07d44e's fractions' rules
        // are 46.8pt apart at 12pt in Word's print, a line of two 15.8pt
        // YaHei rows and the rule's room under 0.3 em more.)
        let gap = entry.size * 0.3
        var tops: [Double] = []
        var y = 0.0
        for b in boxes { tops.append(y); y += b.ascent + b.descent + gap }
        let height = y - gap
        let wide = boxes.enumerated().map { ($0.offset == 0 ? 0 : indent) + $0.element.width }.max() ?? 0
        let first = boxes[0].ascent
        let broken = Box(width: wide, ascent: first, descent: height - first) { canvas, at in
            for (k, b) in boxes.enumerated() {
                b.draw(canvas, Offset(at.dx + (k == 0 ? 0 : indent), at.dy - first + tops[k] + b.ascent))
            }
        }
        lock.lock()
        entries[attachment.id]?.fits.append(broken)
        lock.unlock()
        return (wide, height, first)
    }

    /// The equation `node` laid out on its own, its runs `size` points
    /// where they say none: for a sheet's text box, which draws it where
    /// its paragraph stands. nil for one with nothing in it.
    static func box(_ node: XNode, size: Double) -> Box? {
        let box = Layout(display: node.name == "m:oMathPara", inlineText: node.name != "m:oMathPara").row(node, size: size, level: 0)
        return box.width > 0 ? box : nil
    }

    /// Whether an equation is registered for `attachment`.
    static func has(_ attachment: ImageAttachment) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[attachment.id] != nil
    }

    /// Draws the equation registered for `attachment` into `rect`.
    static func paint(_ attachment: ImageAttachment, _ canvas: any Canvas, _ rect: Rect, _ pxPerPt: Double) -> Bool {
        lock.lock()
        let entry = entries[attachment.id]
        lock.unlock()
        guard let entry else { return false }
        // (The form laid out to this rectangle's width, where one was.)
        let wide = rect.width / max(pxPerPt, 0.0001)
        let box = entry.fits.last(where: { abs($0.width - wide) < 1.5 }) ?? entry.box
        canvas.save()
        canvas.translate(rect.left, rect.top)
        canvas.scale(pxPerPt, pxPerPt)
        box.draw(canvas, Offset(0, box.ascent))
        canvas.restore()
        return true
    }

    /// The faces an equation is set in: Cambria's stand-in, the serif
    /// Cambria Math is drawn like, then the platform's math faces for what
    /// it lacks.
    static var family: String { OfficeFonts.drawn("Cambria") }
    static let fallback = ["STIX Two Math", "DejaVu Math TeX Gyre", "Noto Sans Math"]

    /// Keeps the painters a drawing needs alive as long as the drawing.
    private final class Painter {
        let tp: TextPainter
        let ascent: Double
        let descent: Double
        let baseline: Double
        init(_ text: String, size: Double, italic: Bool, color: Color, family: String? = nil, height: Double? = nil) {
            tp = TextPainter(text: TextSpan(text: text, style: TextStyle(color: color, fontSize: size, fontStyle: italic ? .italic : .normal,
                                                                          height: height,
                                                                          fontFamily: family ?? WriterMath.family,
                                                                          fontFamilyFallback: WriterMath.fallback + RichTextTheme.glyphFallback)),
                             textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: .infinity)
            let m = tp.computeLineMetrics().first
            baseline = m?.baseline ?? size * 0.8
            // (The box is the face's own height, not the height a fallback face's glyph makes
            // of the line: Word's math boxes stand on the math font's metrics. A Greek σ in
            // Caladea's run took DejaVu's taller ascent and descent, and lo-4aa628bd's row
            // was 2pt taller than Word's, its σ 1.7pt low.)
            var fa = m?.ascent ?? size * 0.8, fd = m?.descent ?? size * 0.2
            if text.unicodeScalars.contains(where: { $0.value > 0x24F }) {
                let ref = TextPainter(text: TextSpan(text: "x", style: TextStyle(color: color, fontSize: size, fontStyle: italic ? .italic : .normal,
                                                                                 height: height, fontFamily: family ?? WriterMath.family,
                                                                                 fontFamilyFallback: WriterMath.fallback + RichTextTheme.glyphFallback)),
                                      textDirection: .ltr)
                ref.layout(minWidth: 0, maxWidth: .infinity)
                if let r = ref.computeLineMetrics().first { fa = min(fa, r.ascent); fd = min(fd, r.descent) }
            }
            ascent = fa
            descent = fd
        }
    }

    private final class LeadRuns { var ids = Set<ObjectIdentifier>() }
    private struct Layout {
        let leadRuns = LeadRuns()
        let display: Bool
        /// Set in a line of text (not a display equation): where Word's print sets fractions and scripts its own way.
        var inlineText = false
        let ink = Color(0xFF000000)

        /// The size at a script level: 0.73 of the one above, to half.
        func scriptSize(_ size: Double, _ level: Int) -> Double {
            // (Word's print of a 12pt equation: a fraction's parts 8.5pt, a script in them 7.0 — half points.)
            if inlineText, RichTextTheme.wordWindowsPages, level >= 1 { return (size * (level == 1 ? 0.7 : 0.6) * 2).rounded() / 2 }
            return max(size * 0.5, size * pow(0.73, Double(min(level, 2))))
        }

        /// A string set as one piece, its baseline at the box's.
        /// (Not clamped to Cambria Math's 0.95 em / 0.22 em: that made xb fra-g255-612f49, xd 0810551f and zh-db07d44e
        /// lower and gained nothing; was tried for jpn-z22855378-6fca0f p8's equation is 20.5 over / 10.7 under
        /// at 12pt in Word's print, 25.3 / 14.0 in ours.)
        func cam(_ v: Double, _ size: Double, _ em: Double) -> Double {
            v
        }

        func text(_ s: String, size: Double, italic: Bool, family: RichResolvedFace? = nil) -> Box {
            guard !s.isEmpty else { return .empty }
            // Word's formula letters are the mathematical italic ones (U+1D44E on): OMML letters
            // default to math italic, and its print has those code points, not slanted plain letters.
            var s = s, italic = italic
            if italic, RichTextTheme.wordWindowsPages, s.unicodeScalars.allSatisfy({ $0.isASCII }) {
                s = String(String.UnicodeScalarView(s.unicodeScalars.map { u -> Unicode.Scalar in
                    switch u.value {
                    case 0x41 ... 0x5A: return Unicode.Scalar(0x1D434 + u.value - 0x41)!
                    case 0x68: return Unicode.Scalar(0x210E)!
                    case 0x61 ... 0x7A: return Unicode.Scalar(0x1D44E + u.value - 0x61)!
                    default: return u
                    }
                }))
                italic = false
                // Each letter stands at Cambria Math's advance, not the fallback face's own.
                let adv = OfficeFonts.cambriaMathAdvances
                let glyphs = s.unicodeScalars.map { String($0) }
                if !s.unicodeScalars.contains(where: { $0.isASCII }), s.unicodeScalars.allSatisfy({ adv[$0.value] != nil }) {
                    let ps = glyphs.map { Painter($0, size: size, italic: false, color: ink, family: family?.family, height: family?.naturalHeight) }
                    var xs: [Double] = [], x = 0.0
                    for u in s.unicodeScalars { xs.append(x); x += adv[u.value]! * size }
                    let total = x
                    return Box(width: total, ascent: cam(ps.map(\.ascent).max() ?? 0, size, 0.95), descent: cam(ps.map(\.descent).max() ?? 0, size, 0.22), inkUp: size * 0.7, inkDown: size * 0.2) { canvas, at in
                        for (i, q) in ps.enumerated() { q.tp.paint(canvas, Offset(at.dx + xs[i], at.dy - q.baseline)) }
                    }
                }
            }
            let p = Painter(s, size: size, italic: italic, color: ink, family: family?.family, height: family?.naturalHeight)
            return Box(width: p.tp.width, ascent: cam(p.ascent, size, 0.95), descent: cam(p.descent, size, 0.22), inkUp: size * 0.7, inkDown: size * 0.2) { canvas, at in
                p.tp.paint(canvas, Offset(at.dx, at.dy - p.baseline))
            }
        }

        /// Boxes side by side on one baseline.
        func hbox(_ boxes: [Box]) -> Box {
            let parts = boxes.filter { $0.width > 0 || $0.ascent > 0 }
            guard !parts.isEmpty else { return .empty }
            var xs: [Double] = []
            var x = 0.0
            for b in parts { xs.append(x); x += b.width }
            return Box(width: x, ascent: parts.map(\.ascent).max() ?? 0, descent: parts.map(\.descent).max() ?? 0, inkUp: parts.map(\.iu).max() ?? 0, inkDown: parts.map(\.idn).max() ?? 0) { canvas, at in
                for (b, dx) in zip(parts, xs) { b.draw(canvas, Offset(at.dx + dx, at.dy)) }
            }
        }

        /// A gap of `w` points.
        func space(_ w: Double) -> Box { Box(width: w, ascent: 0, descent: 0) { _, _ in } }

        /// A box moved up (negative: down) by `dy` points.
        func raised(_ b: Box, _ dy: Double) -> Box {
            Box(width: b.width, ascent: max(0, b.ascent + dy), descent: max(0, b.descent - dy), inkUp: max(0, b.iu + dy), inkDown: max(0, b.idn - dy)) { canvas, at in
                b.draw(canvas, Offset(at.dx, at.dy - dy))
            }
        }

        /// The face a run sets its East Asian characters in: its own
        /// `w:eastAsia` face (zh-db07d44e's equations say 標楷體, YaHei to
        /// Word on the Mac, its lines that face's height), else the math
        /// faces' fallback.
        func eastAsianFamily(_ r: XNode) -> RichResolvedFace? {
            r.first("w:rPr")?.first("w:rFonts")?["w:eastAsia"].flatMap { OfficeFonts.face($0, eastAsian: true) }
        }
        func wide(_ s: String) -> Bool { s.unicodeScalars.contains { $0.value >= 0x2E80 } }

        /// A run's text: letters italic unless the run is plain
        /// (`m:sty p`, `m:nor`), operators spaced as Word sets them.
        // (A run that begins its row: a sign at its start has nothing on its left to stand off from —
        // Word's print of jpn-z22855378-6fca0f's exp[−(Δx+d0)²/4σ²] sets the minus against its bracket.)
        func run(_ r: XNode, size: Double, level: Int) -> Box {
            var own = scriptSize(size, level)
            if let sz = r.first("w:rPr")?.first("w:sz")?["w:val"].flatMap(Double.init), sz > 0 { own = scriptSize(sz / 2, level) }
            let plain = r.first("m:rPr")?.first("m:sty")?["m:val"] == "p" || r.first("m:rPr")?.first("m:nor") != nil
            let s = r.all("m:t").map(\.text).joined()
            var parts: [Box] = []
            var piece = ""
            var pieceItalic = false
            let ea = eastAsianFamily(r)
            func flush() {
                if !piece.isEmpty { parts.append(text(piece, size: own, italic: pieceItalic, family: wide(piece) ? ea : nil)) }
                piece = ""
            }
            var firstChar = true
            for ch in s {
                let leads = firstChar && leadRuns.ids.contains(ObjectIdentifier(r)) && inlineText && RichTextTheme.wordWindowsPages && "+−-±∓".contains(ch)
                firstChar = false
                if "=+−-±×÷<>≤≥≈≠∓→←⇒∈∉⊂⊃∪∩".contains(ch) {
                    flush()
                    // (A relation or a binary operator stands a fifth of
                    // an em off what is beside it, in scripts less.)
                    var gap = level == 0 ? own * 0.22 : own * 0.1
                    var glyph = text(String(ch == "-" ? "−" : ch), size: own, italic: false)
                    if RichTextTheme.wordWindowsPages && inlineText {
                        // Cambria Math (Word's print of jpn-z22855378-6fca0f): =, + and − advance
                        // 0.75 em (the fallback face's 0.56), a relation stands 5/18 em and a binary
                        // operator 4/18 em off its neighbours, and in a script none at all.
                        let relation = "=<>≤≥≈≠→←⇒∈∉⊂⊃".contains(ch)
                        gap = level == 0 ? own * (relation ? 5.0 / 18 : 4.0 / 18) : 0
                        if "=+−-".contains(ch) {
                            let w = own * 0.75, inner = glyph
                            glyph = Box(width: w, ascent: inner.ascent, descent: inner.descent) { canvas, at in
                                inner.draw(canvas, Offset(at.dx + (w - inner.width) / 2, at.dy))
                            }
                        }
                    }
                    if !leads { parts.append(space(gap)) }
                    parts.append(glyph)
                    // (A sign leading its row, Word's exp[−(Δx+d0)²/4σ²]: ink to ink 2.0 pt of 12 to the bracket; our bracket carries 1.0 pt of side space, so 1/12 em, after it.)
                    parts.append(space(leads ? own / 12 : gap))
                    continue
                }
                if ch == ",", level == 0, inlineText, RichTextTheme.wordWindowsPages {
                    // (Word sets a thin space, 1/6 em, after a comma.)
                    flush()
                    parts.append(text(",", size: own, italic: false))
                    parts.append(space(own / 6))
                    continue
                }
                let italic = !plain && ch.isLetter && ch.unicodeScalars.allSatisfy { $0.value < 0x2E80 }
                if italic != pieceItalic { flush(); pieceItalic = italic }
                piece.append(ch)
            }
            flush()
            return hbox(parts)
        }

        /// A display equation's pieces a line may part between, each with
        /// whether a line may start with it (an operator): its top-level
        /// pieces, a run parted at its operators, and a bracket round
        /// what follows opened up — its fences pieces of their own.
        func pieces(_ node: XNode, size: Double) -> [(box: Box, breaksBefore: Bool)] {
            let math = node.name == "m:oMathPara" ? node.all("m:oMath") : [node]
            var out: [(box: Box, breaksBefore: Bool)] = []
            func add(_ n: XNode) {
                switch n.name {
                case "m:r":
                    out += runPieces(n, size: size)
                case "m:d" where n.all("m:e").count == 1:
                    let pr = n.first("m:dPr")
                    let beg = pr?.first("m:begChr")?["m:val"] ?? "("
                    let end = pr?.first("m:endChr")?["m:val"] ?? ")"
                    let s = runSize(n.first("m:e"), size, 0)
                    if !beg.isEmpty { out.append((text(beg, size: s, italic: false), false)) }
                    for c in n.first("m:e")?.children ?? [] { add(c) }
                    if !end.isEmpty { out.append((text(end, size: s, italic: false), false)) }
                default:
                    let b = element(n, size: size, level: 0)
                    if b.width > 0 || b.ascent > 0 { out.append((b, false)) }
                }
            }
            for m in math { for c in m.children { add(c) } }
            return out
        }

        /// A run's pieces: its text between operators, each operator with
        /// its spacing a piece a line may start with.
        func runPieces(_ r: XNode, size: Double) -> [(box: Box, breaksBefore: Bool)] {
            var own = scriptSize(size, 0)
            if let sz = r.first("w:rPr")?.first("w:sz")?["w:val"].flatMap(Double.init), sz > 0 { own = scriptSize(sz / 2, 0) }
            let plain = r.first("m:rPr")?.first("m:sty")?["m:val"] == "p" || r.first("m:rPr")?.first("m:nor") != nil
            let s = r.all("m:t").map(\.text).joined()
            var out: [(box: Box, breaksBefore: Bool)] = []
            var parts: [Box] = []
            var piece = ""
            var pieceItalic = false
            var opens = false
            let ea = eastAsianFamily(r)
            func flush() { if !piece.isEmpty { parts.append(text(piece, size: own, italic: pieceItalic, family: wide(piece) ? ea : nil)) }; piece = "" }
            func close() { flush(); if !parts.isEmpty { out.append((hbox(parts), opens)) }; parts = []; opens = false }
            for ch in s {
                if "=+−-±×÷<>≤≥≈≠∓→←⇒∈∉⊂⊃∪∩".contains(ch) {
                    close()
                    opens = true
                    let gap = own * 0.22
                    parts.append(space(gap))
                    parts.append(text(String(ch == "-" ? "−" : ch), size: own, italic: false))
                    parts.append(space(gap))
                    continue
                }
                let italic = !plain && ch.isLetter && ch.unicodeScalars.allSatisfy { $0.value < 0x2E80 }
                if italic != pieceItalic { flush(); pieceItalic = italic }
                piece.append(ch)
            }
            close()
            return out
        }

        /// What `node` holds, in a row: its children, as each one sets.
        func row(_ node: XNode?, size: Double, level: Int) -> Box {
            guard let node else { return .empty }
            if node.attrs["cont"] == nil, let head = node.children.first(where: { !$0.name.hasSuffix("Pr") }), head.name == "m:r" { leadRuns.ids.insert(ObjectIdentifier(head)) }
            return hbox(node.children.map { element($0, size: size, level: level) })
        }

        /// The size a run under `node` gives, else `size`, at `level`.
        func runSize(_ node: XNode?, _ size: Double, _ level: Int = 0) -> Double {
            guard let sz = node?.descendant("w:sz")?["w:val"].flatMap(Double.init), sz > 0 else { return scriptSize(size, level) }
            return scriptSize(sz / 2, level)
        }

        func element(_ n: XNode, size: Double, level: Int) -> Box {
            switch n.name {
            case "m:r":
                return run(n, size: size, level: level)
            case "w:del", "m:ctrlPr", "w:rPr", "m:rPr", "w:bookmarkStart", "w:bookmarkEnd", "w:proofErr", "m:argPr":
                return .empty
            case _ where n.name.hasSuffix("Pr"):
                return .empty
            case "m:sSub", "m:sSup", "m:sSubSup", "m:sPre":
                let base = row(n.first("m:e"), size: size, level: level)
                let sub = n.first("m:sub").map { row($0, size: size, level: level + 1) }
                let sup = n.first("m:sup").map { row($0, size: size, level: level + 1) }
                let s = runSize(n.first("m:e"), size, level)
                let scripts = stackScripts(sub: sub, sup: sup, size: s, base: base)
                return n.name == "m:sPre" ? hbox([scripts, base]) : hbox([base, scripts])
            case "m:nary":
                return nary(n, size: size, level: level)
            case "m:f":
                // (Its parts in the inline style: zh-c2c92639's ∑ over A has
                // its limits beside it in Word's print, the sign unenlarged.)
                let inner = Layout(display: false, inlineText: inlineText)
                // (And in a line of text — no display equation — at script size: 20d9968b's
                // n over k stands 7.6pt in a 10.6pt line in Word's print, 0.72 of it.)
                let part = display ? level : level + 1
                let num = inner.row(n.first("m:num"), size: size, level: part)
                let den = inner.row(n.first("m:den"), size: size, level: part)
                // (Word sets a display fraction's rule and stacking at the equation's size, whatever one run
                // inside it is: jpn-z22855378-6fca0f p8's x-bar at 14pt in a 12pt fraction.)
                let s = RichTextTheme.wordWindowsPages && !inlineText ? scriptSize(size, level) : runSize(n.first("m:num"), size, level)
                if n.first("m:fPr")?.first("m:type")?["m:val"] == "lin" {
                    return hbox([num, text("/", size: s, italic: false), den])
                }
                return fraction(num, den, size: s)
            case "m:d":
                return delimited(n, size: size, level: level)
            case "m:rad":
                return radical(n, size: size, level: level)
            case "m:func":
                let s = runSize(n.first("m:fName"), size, level)
                return hbox([row(n.first("m:fName"), size: size, level: level), space(s * 0.17), row(n.first("m:e"), size: size, level: level)])
            case "m:acc":
                let base = row(n.first("m:e"), size: size, level: level)
                let chr = n.first("m:accPr")?.first("m:chr")?["m:val"] ?? "\u{0302}"
                let mark = text(Self.spacingAccent(chr), size: runSize(n.first("m:e"), size, level), italic: false)
                // (An accent over a letter is a mark of the letter's own line box, not a box stacked on it:
                // Word sets the bar on the letter's baseline, as one glyph with a combining mark, so the
                // equation is no taller for it. Over something taller than the line's own ascent, stacked.)
                if base.ascent <= mark.ascent + 0.01 {
                    let w = max(base.width, mark.width)
                    // The mark clears the letter's ink: its own glyph sits at a fixed height above the baseline
                    // (a macron high, a tilde low), so it is lifted by what the letter's top (x-height, or cap/ascender height) lacks.
                    let letters = (n.first("m:e")?.all("m:t").map(\.text).joined() ?? "")
                    let tall = letters.first.map { $0.isUppercase || $0.isNumber || "bdfhklt\u{3C8}\u{3C6}\u{2113}\u{3B4}\u{3B8}\u{3BB}\u{3B2}\u{3B6}\u{3BE}".contains($0) } ?? false
                    let markBottom: Double = (chr == "\u{0303}" || chr == "~") ? 0.28 : (chr == "\u{0302}" || chr == "^") ? 0.45 : 0.50
                    let gap: Double = markBottom < 0.5 ? 0.15 : 0.03
                    let lift = max(0, (tall ? 0.70 : 0.46) + gap - markBottom) * size
                    return Box(width: w, ascent: mark.ascent + lift, descent: base.descent) { canvas, at in
                        base.draw(canvas, Offset(at.dx + (w - base.width) / 2, at.dy))
                        mark.draw(canvas, Offset(at.dx + (w - mark.width) / 2, at.dy - lift))
                    }
                }
                return over(base, mark, gap: 0)
            case "m:bar":
                let base = row(n.first("m:e"), size: size, level: level)
                let top = n.first("m:barPr")?.first("m:pos")?["m:val"] == "top"
                return bar(base, top: top, size: runSize(n.first("m:e"), size, level))
            case "m:limLow", "m:limUpp":
                let base = row(n.first("m:e"), size: size, level: level)
                let lim = row(n.first("m:lim"), size: size, level: level + 1)
                let gap = runSize(n.first("m:e"), size, level) * 0.05
                return n.name == "m:limLow" ? under(base, lim, gap: gap) : over(base, lim, gap: gap)
            case "m:groupChr":
                let base = row(n.first("m:e"), size: size, level: level)
                let chr = n.first("m:groupChrPr")?.first("m:chr")?["m:val"] ?? "\u{23DF}"
                let mark = text(chr, size: runSize(n.first("m:e"), size, level), italic: false)
                return n.first("m:groupChrPr")?.first("m:pos")?["m:val"] == "top" ? over(base, mark, gap: 0) : under(base, mark, gap: 0)
            case "m:eqArr":
                let s = runSize(n, size, level)
                return column(n.all("m:e").map { row($0, size: size, level: level) }, gap: s * 0.25, size: s)
            case "m:m":
                return matrix(n, size: size, level: level)
            default:
                // (A wrapper — `w:ins`, `m:e`, `m:box`, `m:oMath` — or
                // what this does not lay out: its children in a row.)
                return row(n, size: size, level: level)
            }
        }

        /// Sub- and superscripts beside a base, stacked.
        func stackScripts(sub: Box?, sup: Box?, size: Double, base: Box, fixed: (Double, Double)? = nil) -> Box {
            // (A superscript's baseline 0.38 em up, a subscript's 0.18 down,
            // a tenth more each where both stand; past a taller base than a
            // letter's, that much further. zh-c2c92639's "C" over "dm" in
            // Word's print reaches 3.9pt under the line at 10.5pt; set from
            // the scripts' own heights, ours went 6.9 down and its line
            // took a second grid pitch.)
            let both = sub != nil && sup != nil ? size * 0.1 : 0
            let up = fixed?.0 ?? max(size * 0.38, base.ascent - size * 0.95 + size * 0.38) + both
            let down = fixed?.1 ?? max(size * 0.18, base.descent - size * 0.22 + size * 0.18) + both
            var parts: [Box] = []
            // (Drawn subscript first, as Word's print sets them: its glyphs come out base,
            // subscript with its own scripts, then the superscript — lo-4aa628bd's
            // "σEx2" is one line of Word's print with the outer 2 apart.)
            // (A script reaches no higher over its own baseline than 0.85 of its size, as an
            // inline equation's line does: lo-4aa628bd's 8pt "2" over a σ is 6.8 above its
            // baseline in Word's print, 7.6 in the face's own ascent; a superscript with no subscript is not capped (lo-6e71a4d5's "A=πr2" stands where it did); the row stood 2pt
            // taller than Word's.)
            let cap = size * 0.73 * 0.85
            func capped(_ b: Box) -> Box { Box(width: b.width, ascent: min(b.ascent, cap), descent: b.descent, inkUp: min(b.iu, cap), inkDown: b.idn, draw: b.draw) }
            if let sub { parts.append(raised(capped(sub), -down)) }
            if let sup { parts.append(raised(sub != nil ? capped(sup) : sup, up)) }
            guard !parts.isEmpty else { return .empty }
            let w = parts.map(\.width).max() ?? 0
            return Box(width: w + size * 0.05, ascent: parts.map(\.ascent).max() ?? 0, descent: parts.map(\.descent).max() ?? 0, inkUp: parts.map(\.iu).max() ?? 0, inkDown: parts.map(\.idn).max() ?? 0) { canvas, at in
                for p in parts { p.draw(canvas, at) }
            }
        }

        /// `top` centred over `base`, `gap` points between.
        func over(_ base: Box, _ top: Box, gap: Double) -> Box {
            let w = max(base.width, top.width)
            return Box(width: w, ascent: base.ascent + gap + top.ascent + top.descent, descent: base.descent, inkUp: base.ascent + gap + top.iu + top.idn, inkDown: base.idn) { canvas, at in
                base.draw(canvas, Offset(at.dx + (w - base.width) / 2, at.dy))
                top.draw(canvas, Offset(at.dx + (w - top.width) / 2, at.dy - base.ascent - gap - top.descent))
            }
        }

        /// `low` centred under `base`.
        func under(_ base: Box, _ low: Box, gap: Double) -> Box {
            let w = max(base.width, low.width)
            return Box(width: w, ascent: base.ascent, descent: base.descent + gap + low.ascent + low.descent, inkUp: base.iu, inkDown: base.descent + gap + low.iu + low.idn) { canvas, at in
                base.draw(canvas, Offset(at.dx + (w - base.width) / 2, at.dy))
                low.draw(canvas, Offset(at.dx + (w - low.width) / 2, at.dy + base.descent + gap + low.ascent))
            }
        }

        /// Rows stacked, each centred, the stack's middle on the math axis.
        func column(_ rows: [Box], gap: Double, size: Double) -> Box {
            guard rows.count > 1 else { return rows.first ?? .empty }
            let w = rows.map(\.width).max() ?? 0
            let total = rows.reduce(0) { $0 + $1.ascent + $1.descent } + gap * Double(rows.count - 1)
            let ascent = total / 2 + size * 0.27
            return Box(width: w, ascent: ascent, descent: max(0, total - ascent)) { canvas, at in
                var y = at.dy - ascent
                for r in rows {
                    y += r.ascent
                    r.draw(canvas, Offset(at.dx + (w - r.width) / 2, y))
                    y += r.descent + gap
                }
            }
        }

        /// An n-ary operator (∑, ∫, ∏…) with its limits and what it acts on.
        func nary(_ n: XNode, size: Double, level: Int) -> Box {
            let pr = n.first("m:naryPr")
            let chr = pr?.first("m:chr")?["m:val"] ?? "\u{222B}"
            let integral = ["\u{222B}", "\u{222C}", "\u{222D}", "\u{222E}"].contains(chr)
            // (Inline, the limits stand beside the sign whatever it says.)
            let limits = display ? pr?.first("m:limLoc")?["m:val"] ?? (integral ? "subSup" : "undOvr") : "subSup"
            let s = runSize(n.first("m:e") ?? n, size, level)
            // (A display equation's ∑ is Cambria Math's large variant, the face's own
            // glyph at the text size: ink 1.240 em over the baseline to 0.669 under it,
            // 1.326 em advance (read from the Cambria Math subset in Word's own PDFs, as
            // the constants below: its MATH table). The stand-in's ∑ is 0.667 em tall, so
            // it is drawn 2.864 times larger, its ink on the variant's.)
            let big = display && level == 0 && chr == "\u{2211}"
            let opSize = display && level == 0 && !big ? s * 1.6 : s
            var op: Box
            if big {
                let glyph = text(chr, size: s * 2.864, italic: false)
                op = Box(width: s * 1.326, ascent: s * 1.240, descent: s * 0.669, inkUp: s * 1.240, inkDown: s * 0.669) { canvas, at in
                    glyph.draw(canvas, Offset(at.dx - s * 0.374, at.dy + s * 0.669))
                }
            } else {
                op = raised(text(chr, size: opSize, italic: false), -(opSize - s) * 0.35)
            }
            let hidden = { (name: String) in pr?.first(name).map { ["1", "on", "true"].contains($0["m:val"] ?? "1") } ?? false }
            let sub = hidden("m:subHide") ? nil : n.first("m:sub").map { row($0, size: size, level: level + 1) }
            let sup = hidden("m:supHide") ? nil : n.first("m:sup").map { row($0, size: size, level: level + 1) }
            var withLimits = op
            if limits == "undOvr" {
                // (Cambria Math: the upper limit's baseline at least 500/2048 em over the
                // sign, the lower's at least 1240/2048 under it, each at least 133/2048 em
                // clear of the sign; the limit's ink being about 0.75 of its size tall.)
                if let sup, sup.width > 0 {
                    withLimits = over(withLimits, sup, gap: big ? max(s * 0.244 - sup.descent, s * 0.065) : s * 0.08)
                }
                if let sub, sub.width > 0 {
                    withLimits = under(withLimits, sub, gap: big ? max(s * 0.605, s * 0.065 + min(sub.ascent, s * 0.55)) - sub.ascent : s * 0.08)
                }
            } else {
                // (Cambria Math, beside: the superscript's baseline 460/2048 em under the
                // sign's top, the subscript's 320/2048 em under its foot; zh-c2c92639's
                // sums at 10.6pt: 10.7 up, 8.7 down.)
                // (The inline sign: its limits' baselines 0.349 em over and 0.292 em under the line,
                // read from zh-c2c92639's inline sum in Word's print: the face's 0.70 em
                // ink top less 0.35, the 0.21 em it hangs plus 0.08.)
                let fixed: (Double, Double)? = big ? (op.ascent - s * 0.282, op.descent + s * 0.222)
                    : chr == "\u{2211}" ? (s * 0.292, s * 0.359) : nil
                withLimits = hbox([op, stackScripts(sub: sub, sup: sup, size: s, base: op, fixed: fixed)])
            }
            return hbox([withLimits, space(s * 0.12), row(n.first("m:e"), size: size, level: level)])
        }

        /// A stacked fraction on the math axis.
        func fraction(_ num: Box, _ den: Box, size: Double) -> Box {
            // (Close about its rule: zh-c2c92639's "∑…/A", 10.5pt, stands
            // 28pt from its numerator's top to its denominator's foot in
            // Word's print.)
            let axis = size * 0.27, rule = max(0.4, size * 0.05), gap = size * 0.06, pad = size * 0.08
            let w = max(num.width, den.width) + 2 * pad
            // (A fraction in a line of text — no display equation: Word's print of jpn-z22855378-6fca0f's
            // exp[-(Δx+d0)²/4σ²] at 12pt has the rule 3.45pt over the baseline, the numerator's
            // baseline 7.1 over it and the denominator's 6.0 under it, so the equation is 21.5pt tall
            // and the 18pt-grid line takes two pitches.)
            let text = inlineText && RichTextTheme.wordWindowsPages
            let numUp = text ? size * 0.592 : 0, denDown = text ? size * 0.5 : 0
            // (A display fraction in Word's print, jpn-z22855378-6fca0f p8 at 12pt: the rule 3.8pt over the
            // baseline, the numerator's baseline 9.1 over it and the denominator's 8.1 under it, whatever
            // they hold; a taller numerator or denominator is pushed clear of the rule.)
            let wd = RichTextTheme.wordWindowsPages && !inlineText
            let dRule = size * 0.317
            let dNum = max(size * 0.758, dRule + rule / 2 + gap + min(num.descent, size * 0.3))
            let dDen = max(size * 0.675, rule / 2 + gap + min(den.ascent, size * 0.75) - dRule)
            let ascent = wd ? dNum + num.ascent : text ? numUp + num.ascent : axis + rule / 2 + gap + num.descent + num.ascent
            let descent = wd ? dDen + den.descent : text ? denDown + den.descent : max(0, gap + rule / 2 - axis + den.ascent + den.descent)
            let ruleUp = wd ? dRule : text ? size * 0.2875 : axis
            return Box(width: w, ascent: ascent, descent: descent, inkUp: wd ? dNum + num.iu : nil, inkDown: wd ? dDen + den.idn : nil) { canvas, at in
                let line = at.dy - ruleUp
                num.draw(canvas, Offset(at.dx + (w - num.width) / 2, wd ? at.dy - dNum : text ? at.dy - numUp : line - rule / 2 - gap - num.descent))
                den.draw(canvas, Offset(at.dx + (w - den.width) / 2, wd ? at.dy + dDen : text ? at.dy + denDown : line + rule / 2 + gap + den.ascent))
                let p = Paint()
                p.style = .stroke
                p.strokeWidth = rule
                p.color = Color(0xFF000000)
                canvas.drawLine(Offset(at.dx + pad / 2, line), Offset(at.dx + w - pad / 2, line), p)
            }
        }

        /// What `m:d` holds between its delimiters, grown to its height.
        func delimited(_ n: XNode, size: Double, level: Int) -> Box {
            let pr = n.first("m:dPr")
            let beg = pr?.first("m:begChr")?["m:val"] ?? "("
            let end = pr?.first("m:endChr")?["m:val"] ?? ")"
            let sep = pr?.first("m:sepChr")?["m:val"] ?? "|"
            let s = runSize(n.first("m:e"), size, level)
            var inner: [Box] = []
            for (k, e) in n.all("m:e").enumerated() {
                if k > 0 { inner.append(text(sep, size: s, italic: false)) }
                inner.append(row(e, size: size, level: level))
            }
            let body = hbox(inner)
            // (In a line of text Word's print leaves the brackets round a fraction at the text's size: jpn-z22855378-6fca0f's exp[…].)
            var tall = inlineText && RichTextTheme.wordWindowsPages ? s : max(s, (body.ascent + body.descent) * 0.95)
            // (Cambria Math's DelimitedSubFormulaMinHeight is 3000/2048 em: a display equation's body whose ink is shorter
            // than that keeps its brackets at the text size. xb jpn-z22855378-158454: arg(h_obs(f)h*_GR(f)) is one line in
            // Word's print, ours had stretched brackets and the superscript broke the line in two. A taller body takes
            // the next size variant of the parenthesis that is at least 0.9 of the body's ink on both sides of the axis;
            // the variant heights are the font's MATH table advanceMeasurements /2048 (lab cambria-math), jpn-z22855378-6fca0f
            // p8: 1.976 em round fractions at 14pt, 2.55 and 2.956 em at 12pt.)
            if RichTextTheme.wordWindowsPages, !inlineText {
                let axis = s * 0.286
                let ink = 2 * max(body.iu - axis, body.idn + axis)
                if ink < 3000.0 / 2048 * s { tall = s } else {
                    let steps = [1898.0, 2475, 3379, 4047, 5223, 6053, 7613, 8881].map { $0 / 2048 }
                    let h = (steps.first { $0 * s >= 0.9 * ink } ?? steps.last!) * s
                    tall = h / 0.853
                }
            }
            func fence(_ c: String) -> Box {
                guard !c.isEmpty else { return .empty }
                let f = text(c, size: tall, italic: false)
                // (Centred on the body, not set on its baseline.)
                let middle = RichTextTheme.wordWindowsPages && !inlineText ? s * 0.286 : (body.ascent - body.descent) / 2
                let r = raised(f, middle - (f.ascent - f.descent) / 2)
                // (A stretched bracket reserves its ink, not its whole font line: the line under a display
                // equation was 11-15 pt too tall in jpn-z22855378-6fca0f p8.)
                guard RichTextTheme.wordWindowsPages, !inlineText else { return r }
                return Box(width: r.width, ascent: min(r.ascent, body.ascent + s * 0.1), descent: min(r.descent, body.descent + s * 0.1), draw: r.draw)
            }
            return hbox([fence(beg), body, fence(end)])
        }

        /// A radical: the sign grown to its body, a rule over it, its
        /// degree small at the left.
        // (Windows Word, a root in a line of text: the sign's ink ends at the rule, so the line is no taller than the rule
        // over its body; a display equation's root keeps the sign's height, xs 5e2af397: lo-98ae9de23e's roots stand in 15.6pt lines of a 13.8pt text, the sign's font line gave 19.)
        func radical(_ n: XNode, size: Double, level: Int) -> Box {
            let body = row(n.first("m:e"), size: size, level: level)
            let s = runSize(n.first("m:e"), size, level)
            let hide = n.first("m:radPr")?.first("m:degHide").map { ["1", "on", "true"].contains($0["m:val"] ?? "1") } ?? false
            let degree = hide ? nil : n.first("m:deg").map { row($0, size: size, level: level + 2) }
            let height = body.ascent + body.descent + s * 0.15
            let sign = text("\u{221A}", size: max(s, height * 0.95), italic: false)
            let rule = max(0.4, s * 0.05)
            // (In a line of text the gap over the body is Cambria Math's text-style 0.05 em, not the display 0.12.)
            let top = body.ascent + s * (RichTextTheme.wordWindowsPages && inlineText ? 0.05 : 0.12)
            let lead = (degree?.width ?? 0) * 0.6
            return Box(width: lead + sign.width + body.width + s * 0.05, ascent: max(top + rule, RichTextTheme.wordWindowsPages && inlineText ? 0 : sign.ascent, (degree?.ascent ?? 0) + top * 0.5),
                       descent: max(body.descent, sign.descent)) { canvas, at in
                degree?.draw(canvas, Offset(at.dx, at.dy - top * 0.5))
                sign.draw(canvas, Offset(at.dx + lead, at.dy + body.descent - sign.descent))
                body.draw(canvas, Offset(at.dx + lead + sign.width, at.dy))
                let p = Paint()
                p.style = .stroke
                p.strokeWidth = rule
                p.color = Color(0xFF000000)
                canvas.drawLine(Offset(at.dx + lead + sign.width * 0.9, at.dy - top), Offset(at.dx + lead + sign.width + body.width + s * 0.05, at.dy - top), p)
            }
        }

        /// A rule over (or under) a body.
        func bar(_ body: Box, top: Bool, size: Double) -> Box {
            let rule = max(0.4, size * 0.05), gap = size * 0.08
            return Box(width: body.width, ascent: body.ascent + (top ? gap + rule : 0), descent: body.descent + (top ? 0 : gap + rule)) { canvas, at in
                body.draw(canvas, at)
                let y = top ? at.dy - body.ascent - gap : at.dy + body.descent + gap
                let p = Paint()
                p.style = .stroke
                p.strokeWidth = rule
                p.color = Color(0xFF000000)
                canvas.drawLine(Offset(at.dx, y), Offset(at.dx + body.width, y), p)
            }
        }

        /// A matrix: its rows stacked, its columns aligned at their centres.
        func matrix(_ n: XNode, size: Double, level: Int) -> Box {
            let rows = n.all("m:mr").map { $0.all("m:e").map { row($0, size: size, level: level) } }
            let cols = rows.map(\.count).max() ?? 0
            guard cols > 0 else { return .empty }
            let s = runSize(n, size, level)
            let gapX = s * 0.6
            var widths = [Double](repeating: 0, count: cols)
            for r in rows { for (c, b) in r.enumerated() { widths[c] = max(widths[c], b.width) } }
            let lines = rows.map { r in
                hbox(r.enumerated().flatMap { c, b -> [Box] in
                    let pad = (widths[c] - b.width) / 2
                    return [space(pad + (c > 0 ? gapX : 0)), b, space(pad)]
                })
            }
            return column(lines, gap: s * 0.2, size: s)
        }

        /// The accent a combining mark stands for, set on its own.
        static func spacingAccent(_ chr: String) -> String {
            switch chr {
            case "\u{0302}": return "^"
            case "\u{0303}": return "~"
            case "\u{0304}", "\u{0305}": return "\u{00AF}"
            case "\u{0307}": return "\u{02D9}"
            case "\u{0308}": return "\u{00A8}"
            case "\u{20D7}": return "\u{2192}"
            default: return chr
            }
        }
    }
}
