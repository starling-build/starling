// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

/// A deck as text, for eyes and for diffs: the round-trip gate reads a
/// file, writes it, reads the result and compares the two dumps.
enum SlidesDump {
    static func text(_ state: DeckState, theme: DeckTheme) -> String {
        func n(_ v: Double) -> String { String(format: "%.1f", v) }
        func hex(_ c: Color?) -> String { c.map { String(format: "#%06X", $0.value & 0xFFFFFF) } ?? "-" }
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
            for s in slide.shapes {
                let kind: String
                switch s.kind {
                case .placeholder(let r): kind = "ph:\(r.rawValue)"
                case .textBox: kind = "text"
                case .geometry(let p): kind = "shape:\(p.rawValue)"
                case .picture(let img): kind = "picture:\(img.data.count)b"
                case .opaque(let o): kind = "kept:\(o.label)"
                case .chart(let c):
                    kind = "chart:\(c.type.rawValue):\(c.series.count)x\(c.categories.count)"
                        + (c.title.map { " \"\($0)\"" } ?? "") + (c.stacked ? (c.percent ? " 100%" : " stacked") : "")
                case .table:
                    let cells = s.text?.paragraphs.compactMap(\.cell) ?? []
                    kind = "table:\((cells.map(\.row).max() ?? -1) + 1)x\((cells.map { $0.column + $0.span }.max() ?? 0))"
                }
                let f = s.frame
                var line = "  \(kind) [\(n(f.left)),\(n(f.top)) \(n(f.width))x\(n(f.height))]"
                if s.rotation != 0 { line += " rot \(n(s.rotation))" }
                if s.autofit && s.fontScale < 1 { line += " fit \(Int((s.fontScale * 100).rounded()))%" }
                if s.fill != nil || s.outline != nil { line += " fill \(hex(s.fill)) line \(hex(s.outline))" }
                if let doc = s.text, !doc.plainText().isEmpty {
                    let first = doc.paragraphs.first { !$0.text.isEmpty }
                    let run = first?.runs.first?.style
                    let t = doc.plainText().replacingAll("\n", with: " / ")
                    line += " \"\(t.count > 48 ? String(t.prefix(48)) + "…" : t)\""
                    if let run {
                        line += " \(run.fontFamily ?? "?") \(run.fontSize.map(n) ?? "?")pt \(hex(run.color))"
                        if run.bold { line += " b" }
                    }
                    if let st = first?.style, st.list != nil { line += " list" }
                }
                out += line + "\n"
            }
            let notes = slide.notes.paragraphs.map(\.text).joined(separator: " / ")
            if !notes.isEmpty { out += "  notes \"\(notes.count > 48 ? String(notes.prefix(48)) + "…" : notes)\"\n" }
        }
        return out
    }
}
