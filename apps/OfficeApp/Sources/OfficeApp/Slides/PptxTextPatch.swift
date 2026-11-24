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
        let paras = body.children.filter { $0.name == "a:p" }
        guard paras.count == old.paragraphs.count, !paras.isEmpty else { return nil }
        let o = old.paragraphs, n = new.paragraphs
        var pre = 0
        while pre < o.count, pre < n.count, o[pre] == n[pre] { pre += 1 }
        var suf = 0
        while suf < o.count - pre, suf < n.count - pre, o[o.count - 1 - suf] == n[n.count - 1 - suf] { suf += 1 }
        let oldMid = Array(o[pre ..< o.count - suf]), newMid = Array(n[pre ..< n.count - suf])
        let srcMid = Array(paras[pre ..< o.count - suf])
        if oldMid.isEmpty && newMid.isEmpty { return xml }
        var replacement: [XNode] = []
        if oldMid.count == newMid.count {
            for k in 0 ..< oldMid.count {
                guard patchParagraph(srcMid[k], old: oldMid[k], new: newMid[k]) else { return nil }
            }
            replacement = srcMid
        } else if oldMid.count == 1, newMid.count >= 2 {
            // Enter: each new paragraph is a copy of the one that was split.
            for p in newMid {
                let copy = clone(srcMid[0])
                guard patchParagraph(copy, old: oldMid[0], new: p) else { return nil }
                replacement.append(copy)
            }
        } else if oldMid.count >= 2, newMid.count == 1 {
            // Backspace or Delete across paragraphs: the first stays, the rest are gone.
            let first = clone(srcMid[0])
            guard patchParagraph(first, old: oldMid[0], new: newMid[0]) else { return nil }
            replacement = [first]
        } else {
            return nil
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
        return PptxXML.serialize(node)
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
        struct Slot { var node: XNode; var text: [UInt16]; var isBreak: Bool }
        var slots: [Slot] = []
        for c in src.children {
            switch c.name {
            case "a:r", "a:fld": slots.append(Slot(node: c, text: Array((c.first("a:t")?.text ?? "").utf16), isBreak: false))
            case "a:br": slots.append(Slot(node: c, text: [10], isBreak: true))
            default: break
            }
        }
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
            if isAnchor {
                if slot.isBreak { return false }
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
            if t.isEmpty { drop.insert(si) }
            else if !slot.isBreak { slot.node.first("a:t")?.text = String(decoding: t, as: UTF16.self) }
            start = end
        }
        guard inserted else { return false }
        let dead = Set(drop.map { ObjectIdentifier(slots[$0].node) })
        src.children = src.children.filter { !dead.contains(ObjectIdentifier($0)) }
        return true
    }
}
