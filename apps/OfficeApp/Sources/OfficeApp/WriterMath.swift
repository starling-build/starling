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
        var draw: (any Canvas, Offset) -> Void
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

    private nonisolated(unsafe) static var entries: [String: Entry] = [:]
    private static let lock = RegistryLock()

    /// Lays out the equation `node` (`m:oMath` or `m:oMathPara`) for the
    /// object attachment `id`, its text `size` points where its runs say
    /// none; its size and baseline (from its top), in points.
    static func register(_ node: XNode, for id: String, size: Double) -> (width: Double, height: Double, baseline: Double)? {
        let display = node.name == "m:oMathPara"
        var box = Layout(display: display).row(node, size: size, level: 0)
        guard box.width > 0 else { return nil }
        // (An equation in a line takes no more of it than its text would:
        // its scripts reach into the line's leading, as Word sets them —
        // zh-c2c92639's "式中：C_dm ——…" lines are one 16.65pt pitch of its
        // grid in Word's print, where the subscript's depth took ours two.
        // It is drawn whole all the same.)
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
        let box = Layout(display: node.name == "m:oMathPara").row(node, size: size, level: 0)
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
            ascent = m?.ascent ?? size * 0.8
            descent = m?.descent ?? size * 0.2
            baseline = m?.baseline ?? ascent
        }
    }

    private struct Layout {
        let display: Bool
        let ink = Color(0xFF000000)

        /// The size at a script level: 0.73 of the one above, to half.
        func scriptSize(_ size: Double, _ level: Int) -> Double { max(size * 0.5, size * pow(0.73, Double(min(level, 2)))) }

        /// A string set as one piece, its baseline at the box's.
        func text(_ s: String, size: Double, italic: Bool, family: RichResolvedFace? = nil) -> Box {
            guard !s.isEmpty else { return .empty }
            let p = Painter(s, size: size, italic: italic, color: ink, family: family?.family, height: family?.naturalHeight)
            return Box(width: p.tp.width, ascent: p.ascent, descent: p.descent) { canvas, at in
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
            return Box(width: x, ascent: parts.map(\.ascent).max() ?? 0, descent: parts.map(\.descent).max() ?? 0) { canvas, at in
                for (b, dx) in zip(parts, xs) { b.draw(canvas, Offset(at.dx + dx, at.dy)) }
            }
        }

        /// A gap of `w` points.
        func space(_ w: Double) -> Box { Box(width: w, ascent: 0, descent: 0) { _, _ in } }

        /// A box moved up (negative: down) by `dy` points.
        func raised(_ b: Box, _ dy: Double) -> Box {
            Box(width: b.width, ascent: max(0, b.ascent + dy), descent: max(0, b.descent - dy)) { canvas, at in
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
            for ch in s {
                if "=+−-±×÷<>≤≥≈≠∓→←⇒∈∉⊂⊃∪∩".contains(ch) {
                    flush()
                    // (A relation or a binary operator stands a fifth of
                    // an em off what is beside it, in scripts less.)
                    let gap = level == 0 ? own * 0.22 : own * 0.1
                    parts.append(space(gap))
                    parts.append(text(String(ch == "-" ? "−" : ch), size: own, italic: false))
                    parts.append(space(gap))
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
                let inner = Layout(display: false)
                let num = inner.row(n.first("m:num"), size: size, level: level)
                let den = inner.row(n.first("m:den"), size: size, level: level)
                let s = runSize(n.first("m:num"), size, level)
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
        func stackScripts(sub: Box?, sup: Box?, size: Double, base: Box) -> Box {
            // (A superscript's baseline 0.38 em up, a subscript's 0.18 down,
            // a tenth more each where both stand; past a taller base than a
            // letter's, that much further. zh-c2c92639's "C" over "dm" in
            // Word's print reaches 3.9pt under the line at 10.5pt; set from
            // the scripts' own heights, ours went 6.9 down and its line
            // took a second grid pitch.)
            let both = sub != nil && sup != nil ? size * 0.1 : 0
            let up = max(size * 0.38, base.ascent - size * 0.95 + size * 0.38) + both
            let down = max(size * 0.18, base.descent - size * 0.22 + size * 0.18) + both
            var parts: [Box] = []
            if let sup { parts.append(raised(sup, up)) }
            if let sub { parts.append(raised(sub, -down)) }
            guard !parts.isEmpty else { return .empty }
            let w = parts.map(\.width).max() ?? 0
            return Box(width: w + size * 0.05, ascent: parts.map(\.ascent).max() ?? 0, descent: parts.map(\.descent).max() ?? 0) { canvas, at in
                for p in parts { p.draw(canvas, at) }
            }
        }

        /// `top` centred over `base`, `gap` points between.
        func over(_ base: Box, _ top: Box, gap: Double) -> Box {
            let w = max(base.width, top.width)
            return Box(width: w, ascent: base.ascent + gap + top.ascent + top.descent, descent: base.descent) { canvas, at in
                base.draw(canvas, Offset(at.dx + (w - base.width) / 2, at.dy))
                top.draw(canvas, Offset(at.dx + (w - top.width) / 2, at.dy - base.ascent - gap - top.descent))
            }
        }

        /// `low` centred under `base`.
        func under(_ base: Box, _ low: Box, gap: Double) -> Box {
            let w = max(base.width, low.width)
            return Box(width: w, ascent: base.ascent, descent: base.descent + gap + low.ascent + low.descent) { canvas, at in
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
            // (A display equation's operator 1.6 times its
            // text, as Word draws ∑: zh-20ff844e's.)
            let opSize = display && level == 0 ? s * 1.6 : s
            let op = raised(text(chr, size: opSize, italic: false), -(opSize - s) * 0.35)
            let hidden = { (name: String) in pr?.first(name).map { ["1", "on", "true"].contains($0["m:val"] ?? "1") } ?? false }
            let sub = hidden("m:subHide") ? nil : n.first("m:sub").map { row($0, size: size, level: level + 1) }
            let sup = hidden("m:supHide") ? nil : n.first("m:sup").map { row($0, size: size, level: level + 1) }
            var withLimits = op
            if limits == "undOvr" {
                if let sup, sup.width > 0 { withLimits = over(withLimits, sup, gap: s * 0.08) }
                if let sub, sub.width > 0 { withLimits = under(withLimits, sub, gap: s * 0.08) }
            } else {
                withLimits = hbox([op, stackScripts(sub: sub, sup: sup, size: s, base: op)])
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
            let ascent = axis + rule / 2 + gap + num.descent + num.ascent
            let descent = max(0, gap + rule / 2 - axis + den.ascent + den.descent)
            return Box(width: w, ascent: ascent, descent: descent) { canvas, at in
                let line = at.dy - axis
                num.draw(canvas, Offset(at.dx + (w - num.width) / 2, line - rule / 2 - gap - num.descent))
                den.draw(canvas, Offset(at.dx + (w - den.width) / 2, line + rule / 2 + gap + den.ascent))
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
            let tall = max(s, (body.ascent + body.descent) * 0.95)
            func fence(_ c: String) -> Box {
                guard !c.isEmpty else { return .empty }
                let f = text(c, size: tall, italic: false)
                // (Centred on the body, not set on its baseline.)
                let middle = (body.ascent - body.descent) / 2
                return raised(f, middle - (f.ascent - f.descent) / 2)
            }
            return hbox([fence(beg), body, fence(end)])
        }

        /// A radical: the sign grown to its body, a rule over it, its
        /// degree small at the left.
        func radical(_ n: XNode, size: Double, level: Int) -> Box {
            let body = row(n.first("m:e"), size: size, level: level)
            let s = runSize(n.first("m:e"), size, level)
            let hide = n.first("m:radPr")?.first("m:degHide").map { ["1", "on", "true"].contains($0["m:val"] ?? "1") } ?? false
            let degree = hide ? nil : n.first("m:deg").map { row($0, size: size, level: level + 2) }
            let height = body.ascent + body.descent + s * 0.15
            let sign = text("\u{221A}", size: max(s, height * 0.95), italic: false)
            let rule = max(0.4, s * 0.05)
            let top = body.ascent + s * 0.12
            let lead = (degree?.width ?? 0) * 0.6
            return Box(width: lead + sign.width + body.width + s * 0.05, ascent: max(top + rule, sign.ascent, (degree?.ascent ?? 0) + top * 0.5),
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
