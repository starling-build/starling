// Typing in a shape (S-P0-1b): the shape is written as its own XML with only the typed text patched in,
// so what the text model does not hold (links, tab stops, right-to-left, character spacing, East Asian
// faces, text outline and gradient fills, the shape's vertical text and adjust values) is not lost.
//
// Shared code (also built for the web): bounds-checked, never traps.

import Foundation
import OfficeText

enum PptxTextPatch {
    /// `xml` (a shape element as read) with the paragraphs of `old` changed into those of `new`, or nil
    /// when the edit is not one this can patch (the caller then writes the shape from the model).
    static func apply(_ xml: String, old: RichDocument, new: RichDocument) -> String? {
        guard let node = XNode.parse(Data(xml.utf8)), let body = node.first("p:txBody") else { return nil }
        if oldEqualsNew(old, new) { return xml }
        return patchBody(body, old: old, new: new) ? PptxXML.serialize(node) : nil
    }

    private static func oldEqualsNew(_ a: RichDocument, _ b: RichDocument) -> Bool { a.paragraphs == b.paragraphs }

    /// The same edit made inside a text body (`p:txBody` or a table cell's `a:txBody`) in place; false when it cannot be.
    static func patchBody(_ body: XNode, old: RichDocument, new: RichDocument) -> Bool {
        let before = body.children.map { clone($0) }
        if patchBodyUnchecked(body, old: old, new: new) { return true }
        body.children = before
        return false
    }

    private static func patchBodyUnchecked(_ body: XNode, old: RichDocument, new: RichDocument) -> Bool {
        let paras = body.children.filter { $0.name == "a:p" }
        guard paras.count == old.paragraphs.count, !paras.isEmpty else { return false }
        let o = old.paragraphs, n = new.paragraphs
        var pre = 0
        while pre < o.count, pre < n.count, o[pre] == n[pre] { pre += 1 }
        var suf = 0
        while suf < o.count - pre, suf < n.count - pre, o[o.count - 1 - suf] == n[n.count - 1 - suf] { suf += 1 }
        let oldMid = Array(o[pre ..< o.count - suf]), newMid = Array(n[pre ..< n.count - suf])
        let srcMid = Array(paras[pre ..< o.count - suf])
        if oldMid.isEmpty && newMid.isEmpty { return true }
        var replacement: [XNode] = []
        if oldMid.count == newMid.count {
            for k in 0 ..< oldMid.count {
                guard patchParagraph(srcMid[k], old: oldMid[k], new: newMid[k]) else { return false }
            }
            replacement = srcMid
        } else if oldMid.count == 1, newMid.count >= 2 {
            // Enter: each new paragraph is a copy of the one that was split.
            for p in newMid {
                let copy = clone(srcMid[0])
                guard patchParagraph(copy, old: oldMid[0], new: p) else { return false }
                replacement.append(copy)
            }
        } else if oldMid.count >= 2, newMid.count == 1 {
            // Backspace or Delete across paragraphs: the first stays, the rest are gone.
            let first = clone(srcMid[0])
            guard patchParagraph(first, old: oldMid[0], new: newMid[0]) else { return false }
            replacement = [first]
        } else {
            return false
        }
        var kids: [XNode] = []
        var placed = false
        for c in body.children {
            if c.name == "a:p" {
                if !placed { kids.append(contentsOf: paras[..<pre]); kids.append(contentsOf: replacement); placed = true }
                if let i = paras.firstIndex(where: { $0 === c }), i >= o.count - suf { kids.append(c) }
            } else {
                kids.append(c)
            }
        }
        body.children = kids
        return true
    }

    private static func clone(_ n: XNode) -> XNode {
        let c = XNode(name: n.name, attrs: n.attrs)
        c.text = n.text
        c.children = n.children.map { clone($0) }
        return c
    }

    private static func styles(_ p: RichParagraph) -> [CharStyle]? {
        var out: [CharStyle] = []
        for r in p.runs { out.append(contentsOf: Array(repeating: r.style, count: max(0, r.length))) }
        return out.count == p.text.utf16.count ? out : nil
    }

    /// One paragraph's text edit, made inside the paragraph's own runs. False when the edit changes a
    /// look, or the paragraph's runs do not read back as the model's text.
    private static func patchParagraph(_ src: XNode, old: RichParagraph, new: RichParagraph) -> Bool {
        guard old.style == new.style, old.image == nil, new.image == nil,
              let oldStyles = styles(old), let newStyles = styles(new) else { return false }
        if old.text == new.text, oldStyles != newStyles { return restyle(src, old: oldStyles, new: newStyles, text: Array(old.text.utf16)) }
        let slots = slots(src)
        let o = Array(old.text.utf16), n = Array(new.text.utf16)
        guard slots.flatMap({ $0.text }) == o else { return false }
        var pre = 0
        while pre < o.count, pre < n.count, o[pre] == n[pre] { pre += 1 }
        var suf = 0
        while suf < o.count - pre, suf < n.count - pre, o[o.count - 1 - suf] == n[n.count - 1 - suf] { suf += 1 }
        let removedEnd = o.count - suf
        let added = Array(n[pre ..< n.count - suf])
        if added.contains(10) { return false }
        for i in 0 ..< pre where oldStyles[i] != newStyles[i] { return false }
        for k in 0 ..< suf where oldStyles[o.count - suf + k] != newStyles[n.count - suf + k] { return false }
        let removing = removedEnd > pre
        if !added.isEmpty {
            // The typed characters take the look of the character they follow (or replace).
            guard !o.isEmpty else { return false }
            let anchor = removing ? pre : max(0, pre - 1)
            for i in pre ..< n.count - suf where newStyles[i] != oldStyles[anchor] { return false }
        }
        // Where the typed text goes: the slot holding the anchor character.
        let anchorIndex = removing ? pre : max(0, pre - 1)
        var start = 0
        var drop = Set<Int>()
        var inserted = added.isEmpty
        for (si, slot) in slots.enumerated() {
            let end = start + slot.text.count
            var t = slot.text
            let isAnchor = !inserted && anchorIndex >= start && anchorIndex < end
            let delFrom = max(pre, start), delTo = min(removedEnd, end)
            var local = max(0, min(t.count, pre - start))
            // A run whose text reads as other characters (a symbol face's), and the marks the reader adds, are kept as they are
            // unless the edit removes a break whole.
            let touched = isAnchor || delTo > delFrom
            if touched, slot.kind == .mark || (slot.kind == .run && !slot.verbatim) { return false }
            if touched, slot.kind == .lineBreak, isAnchor || delTo - delFrom != t.count { return false }
            if isAnchor {
                if slot.kind != .run { return false }
                t.insert(contentsOf: added, at: removing ? local : (pre - start))
                if removing {
                    let a = local + added.count
                    t.removeSubrange(a ..< min(t.count, a + max(0, delTo - delFrom)))
                }
                inserted = true
            } else if delTo > delFrom {
                local = delFrom - start
                t.removeSubrange(local ..< local + (delTo - delFrom))
            }
            if t.isEmpty { if slot.kind != .mark { drop.insert(si) } }
            else if slot.kind == .run, t != slot.text { slot.node.first("a:t")?.text = String(decoding: t, as: UTF16.self) }
            start = end
        }
        guard inserted else { return false }
        let dead = Set(drop.map { ObjectIdentifier(slots[$0].node) })
        src.children = src.children.filter { !dead.contains(ObjectIdentifier($0)) }
        return true
    }

    struct Slot {
        enum Kind { case run, lineBreak, mark }
        var node: XNode
        /// The slot's text as the model reads it (`SlideContext._text`).
        var text: [UInt16]
        var kind: Kind
        /// A run whose text in the file is the text the model holds (not a symbol face's private codes shown as glyphs).
        var verbatim = true
    }

    /// A paragraph's runs, breaks and fields with their text as the reader gives it to the model: a symbol face's private
    /// codes as the glyphs they show, a zero-width mark ahead of a break that opens a line, and one after a closing break.
    /// (A file's paragraph and the model's must read as the same text, or no edit in it can be patched: KEY02's title, a
    /// blank line between two breaks, lost its smtClean and theme colours to a full rewrite when one word was bolded.)
    static func slots(_ p: XNode) -> [Slot] {
        var out: [Slot] = []
        var acc: [UInt16] = []
        for c in p.children {
            switch c.name {
            case "a:r", "a:fld":
                let raw = c.first("a:t")?.text ?? ""
                let shown = SlideContext.symbolsShown(raw, c.first("a:rPr"))
                let t = Array(shown.utf16)
                out.append(Slot(node: c, text: t, kind: .run, verbatim: shown == raw))
                acc += t
            case "a:br":
                let t: [UInt16] = acc.isEmpty || acc.last == 10 ? [0x200B, 10] : [10]
                out.append(Slot(node: c, text: t, kind: .lineBreak))
                acc += t
            default: break
            }
        }
        if acc.last == 10 { out.append(Slot(node: p.first("a:endParaRPr") ?? XNode(name: "a:endParaRPr", attrs: [:]), text: [0x200B], kind: .mark)) }
        return out
    }

    // MARK: A look changed (bold, size, colour, face...): the edited runs' own a:rPr, nothing else.

    /// `c` with the look properties a patch can write put back to `o`'s: what is left must be equal, or the edit is not patchable.
    private static func neutral(_ c: CharStyle, like o: CharStyle) -> CharStyle {
        var x = c
        x.bold = o.bold; x.italic = o.italic; x.underline = o.underline; x.strikethrough = o.strikethrough
        x.fontSize = o.fontSize; x.color = o.color; x.fontFamily = o.fontFamily; x.highlight = o.highlight
        x.script = o.script; x.caps = o.caps; x.smallCaps = o.smallCaps
        return x
    }

    private static func restyle(_ src: XNode, old: [CharStyle], new: [CharStyle], text: [UInt16]) -> Bool {
        for i in old.indices where neutral(new[i], like: old[i]) != old[i] { return false }
        let slots = slots(src)
        guard slots.flatMap({ $0.text }) == text else { return false }
        var start = 0
        var replaced: [(XNode, [XNode])] = []
        for slot in slots {
            let n = slot.text.count
            // Pieces of the run inside which neither the old nor the new look changes.
            var segs: [(Int, Int)] = []
            var a = 0
            if slot.kind != .run {
                // A break (with the mark the reader puts before it) takes the break's look; the reader's paragraph-end mark is
                // the paragraph mark's, which this does not restyle.
                if n > 0, old[start + n - 1] != new[start + n - 1] {
                    guard slot.kind == .lineBreak, patchRPr(slot.node, from: old[start + n - 1], to: new[start + n - 1]) else { return false }
                }
                if slot.kind == .lineBreak { replaced.append((slot.node, [slot.node])) }
                start += n
                continue
            }
            if n > 1 {
                for i in 1 ..< n where old[start + i] != old[start + a] || new[start + i] != new[start + a] {
                    segs.append((a, i)); a = i
                }
            }
            segs.append((a, n))
            var parts: [XNode] = []
            for (x, y) in segs {
                if segs.count > 1, !slot.verbatim { return false }
                let node = segs.count == 1 ? slot.node : clone(slot.node)
                if segs.count > 1 { node.first("a:t")?.text = String(decoding: slot.text[x ..< y], as: UTF16.self) }
                if n > 0, old[start + x] != new[start + x] {
                    guard patchRPr(node, from: old[start + x], to: new[start + x]) else { return false }
                }
                parts.append(node)
            }
            replaced.append((slot.node, parts))
            start += n
        }
        var kids: [XNode] = []
        for c in src.children {
            if let hit = replaced.first(where: { $0.0 === c }) { kids.append(contentsOf: hit.1) } else { kids.append(c) }
        }
        src.children = kids
        return true
    }

    private static let fills: Set<String> = ["a:noFill", "a:solidFill", "a:gradFill", "a:blipFill", "a:pattFill", "a:grpFill"]
    private static let afterHighlight: Set<String> = ["a:uLnTx", "a:uLn", "a:uFillTx", "a:uFill", "a:latin", "a:ea", "a:cs", "a:sym",
                                                      "a:hlinkClick", "a:hlinkMouseOver", "a:rtl", "a:extLst"]
    private static let afterLatin: Set<String> = ["a:ea", "a:cs", "a:sym", "a:hlinkClick", "a:hlinkMouseOver", "a:rtl", "a:extLst"]

    private static func insert(_ child: XNode, into rPr: XNode, before names: Set<String>) {
        let at = rPr.children.firstIndex { names.contains($0.name) } ?? rPr.children.count
        rPr.children.insert(child, at: at)
    }

    private static func patchRPr(_ run: XNode, from o: CharStyle, to w: CharStyle) -> Bool {
        if run.name == "a:br" && run.first("a:rPr") == nil { return true }
        let rPr: XNode
        if let have = run.first("a:rPr") { rPr = have } else {
            rPr = XNode(name: "a:rPr", attrs: [:])
            run.children.insert(rPr, at: 0)
        }
        if o.bold != w.bold { rPr.attrs["b"] = w.bold ? "1" : "0" }
        if o.italic != w.italic { rPr.attrs["i"] = w.italic ? "1" : "0" }
        if o.underline != w.underline { rPr.attrs["u"] = w.underline ? "sng" : "none" }
        if o.strikethrough != w.strikethrough { rPr.attrs["strike"] = w.strikethrough ? "sngStrike" : "noStrike" }
        if o.caps != w.caps || o.smallCaps != w.smallCaps { rPr.attrs["cap"] = w.caps ? "all" : (w.smallCaps ? "small" : "none") }
        if o.script != w.script {
            switch w.script {
            case .superscript: rPr.attrs["baseline"] = "30000"
            case .subscript: rPr.attrs["baseline"] = "-25000"
            case .normal: rPr.attrs["baseline"] = "0"
            }
        }
        if o.fontSize != w.fontSize {
            if let z = w.fontSize { rPr.attrs["sz"] = String(Int((z * 100).rounded())) } else { rPr.attrs["sz"] = nil }
        }
        if o.color != w.color {
            rPr.children.removeAll { fills.contains($0.name) }
            if let c = w.color {
                let fill = XNode(name: "a:solidFill", attrs: [:])
                fill.children = [XNode(name: "a:srgbClr", attrs: ["val": PptxText.hex(c)])]
                let at = rPr.children.firstIndex { $0.name == "a:ln" }.map { $0 + 1 } ?? 0
                rPr.children.insert(fill, at: at)
            }
        }
        if o.highlight != w.highlight {
            rPr.children.removeAll { $0.name == "a:highlight" }
            if let h = w.highlight {
                let node = XNode(name: "a:highlight", attrs: [:])
                node.children = [XNode(name: "a:srgbClr", attrs: ["val": PptxText.hex(h)])]
                insert(node, into: rPr, before: afterHighlight)
            }
        }
        if o.fontFamily != w.fontFamily {
            rPr.children.removeAll { $0.name == "a:latin" }
            if let face = w.fontFamily { insert(XNode(name: "a:latin", attrs: ["typeface": face]), into: rPr, before: afterLatin) }
        }
        return true
    }
}
