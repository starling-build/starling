// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

/// A deck as text, for eyes and for diffs: the round-trip gate reads a
/// file, writes it, reads the result and compares the two dumps.
enum SlidesDump {
    static func n(_ v: Double) -> String { String(printf: "%.1f", v) }
    static func hex(_ c: Color?) -> String { c.map { String(printf: "#%06X", UInt32(truncatingIfNeeded: $0.value & 0xFFFFFF)) } ?? "-" }

    static func text(_ state: DeckState, theme: DeckTheme) -> String {
        var out = "size \(n(state.slideSize.width))x\(n(state.slideSize.height)) fonts \(theme.headingFont)/\(theme.bodyFont)\n"
        for (i, slide) in state.slides.enumerated() {
            let bg: String = {
                guard let b = slide.background else { return "-" }
                if b.image != nil { return "picture" }
                if b.stops.count > 1 { return "gradient \(b.stops.map { hex($0.color) }.joined(separator: ">"))" }
                return hex(b.color)
            }()
            out += "slide \(i + 1) \(slide.layout.rawValue)\(slide.hidden ? " hidden" : "") bg \(bg)\n"
            if !slide.animations.isEmpty {
                let names = slide.animations.map { a in
                    let shape = slide.shapes.firstIndex { $0.id == a.shapeId }.map { "#\($0 + 1)" } ?? "?"
                    return "\(a.effect.rawValue)\(a.effect.hasDirection ? "-" + a.direction.rawValue : "")"
                        + "\(a.start == .onClick ? "" : a.start == .withPrevious ? "+with" : "+after")@\(shape)"
                }
                out += "  animations: " + names.joined(separator: " ") + "\n"
            } else if slide.timingXML != nil && slide.sourceAnimations == nil {
                out += "  animations: kept as read\n"
            }
            for s in slide.shapes { out += shapeLines(s, indent: "  ") }
            let notes = slide.notes.paragraphs.map(\.text).joined(separator: " / ")
            if !notes.isEmpty { out += "  notes \"\(notes.count > 48 ? String(notes.prefix(48)) + "…" : notes)\"\n" }
        }
        return out
    }

    /// One line per shape, and a diagram's rendered shapes under it.
    static func shapeLines(_ s: ShapeState, indent: String) -> String {
        let kind: String
        switch s.kind {
        case .placeholder(let r): kind = "ph:\(r.rawValue)"
        case .textBox: kind = "text"
        case .geometry(let p): kind = "shape:\(p.rawValue)"
        case .picture(let img): kind = "picture:\(img.data.count)b"
        case .opaque(let o): kind = "kept:\(o.label)" + (o.freeform != nil ? ":path" : "")
        case .chart(let c):
            kind = "chart:\(c.type.rawValue):\(c.series.count)x\(c.categories.count)"
                + (c.title.map { " \"\($0)\"" } ?? "") + (c.stacked ? (c.percent ? " 100%" : " stacked") : "")
        case .table:
            let cells = s.text?.paragraphs.compactMap(\.cell) ?? []
            kind = "table:\((cells.map(\.row).max() ?? -1) + 1)x\((cells.map { $0.column + $0.span }.max() ?? 0))"
        }
        let f = s.frame
        var line = "\(indent)\(kind) [\(n(f.left)),\(n(f.top)) \(n(f.width))x\(n(f.height))]"
        if s.rotation != 0 { line += " rot \(n(s.rotation))" }
        if s.autofit && s.fontScale < 1 { line += " fit \(Int((s.fontScale * 100).rounded()))%" }
        if s.fill != nil || s.outline != nil { line += " fill \(hex(s.fill)) line \(hex(s.outline))" }
        if s.fillStyle != nil { line += s.fillStyle?.image != nil ? " fill:picture" : " fill:gradient" }
        if let doc = s.text, !doc.plainText().isEmpty {
            let first = doc.paragraphs.first { !$0.text.isEmpty }
            let run = first?.runs.first?.style
            let t = doc.plainText().replacingAll("\n", with: " / ")
            line += " \"\(t.count > 48 ? String(t.prefix(48)) + "…" : t)\""
            if let run {
                line += " \(run.fontFamily ?? "?") \(run.fontSize.map(n) ?? "?")pt \(hex(run.color))"
                if run.bold { line += " b" }
            }
            if let st = first?.style, st.list != nil {
                line += " list(lvl \(st.listLevel) indent \(n(s.listIndent)) left \(n(st.indentLeft)) first \(n(st.firstLineIndent)))"
            }
            let ins = s.insets
            if ins.left != 7.2 || ins.top != 3.6 { line += " ins \(n(ins.left)),\(n(ins.top)),\(n(ins.right)),\(n(ins.bottom))" }
        }
        var out = line + "\n"
        if case .opaque(let o) = s.kind {
            for r in o.rendering { out += shapeLines(r, indent: indent + "  ") }
        }
        return out
    }
}
