// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Insert → Shapes and Text Box (X-OB-1): a new shape is placed at the active cell, selected, and
// written as its own `xdr:sp` (or `xdr:cxnSp` for a line). Its text is edited through one dialog.
// A shape read from a file is still written back as read; only shapes made here are generated.

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

extension SheetShape {
    /// The shape a choice starts as: Excel's blue fill and darker outline; a text box has neither.
    static func made(_ p: ShapePreset, textBox: Bool) -> SheetShape {
        var s = SheetShape(geometry: p.rawValue, fill: Color(0xFF4472C4), line: Color(0xFF2F528F), lineWidth: 1)
        if textBox {
            s.fill = nil; s.line = nil; s.lineWidth = 0; s.textColor = Color(0xFF000000)
        } else if p.isOpenPath && !p.isLine {
            s.fill = nil; s.line = Color(0xFF4472C4); s.lineWidth = 1.5
        } else if p.isLine {
            s.fill = nil; s.line = Color(0xFF4472C4); s.lineWidth = 1.5
            s.tailArrow = p.rawValue == "straightConnector1"
        } else {
            s.anchor = "ctr"; s.textColor = Color(0xFFFFFFFF)
        }
        return s
    }

    /// The text the shape holds, paragraphs joined by line feeds.
    var plainText: String { paragraphs.map { $0.runs.map(\.text).joined() }.joined(separator: "\n") }

    /// The shape with `text` as its words: the first run's look is kept.
    mutating func setPlainText(_ text: String) {
        let look = paragraphs.first?.runs.first
        let align = paragraphs.first?.align ?? (anchor == "ctr" ? "ctr" : "l")
        paragraphs = text.isEmpty ? [] : text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            var run = look ?? ShapeRun(text: "", size: 11)
            run.text = String(line)
            return ShapeParagraph(align: align, runs: line.isEmpty ? [] : [run], endSize: run.size)
        }
    }

    /// The drawing element for a shape made here. `box` is its anchor's size, kept out of the xfrm (the
    /// anchor places it).
    func xml(id: Int, name: String, textBox: Bool) -> String {
        func rgb(_ c: Color) -> String { String(printf: "%06X", UInt32(truncatingIfNeeded: c.value & 0xFFFFFF)) }
        let isLine = ShapePreset(rawValue: geometry).isLine
        var sp = "<a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/></a:xfrm><a:prstGeom prst=\"\(geometry)\"><a:avLst/></a:prstGeom>"
        sp += fill.map { "<a:solidFill><a:srgbClr val=\"\(rgb($0))\"/></a:solidFill>" } ?? "<a:noFill/>"
        if let line {
            sp += "<a:ln w=\"\(Int((lineWidth * 12700).rounded()))\"><a:solidFill><a:srgbClr val=\"\(rgb(line))\"/></a:solidFill>"
            sp += tailArrow ? "<a:tailEnd type=\"triangle\"/>" : ""
            sp += "</a:ln>"
        } else {
            sp += "<a:ln><a:noFill/></a:ln>"
        }
        let n = Xlsx._esc(name)
        if isLine {
            return "<xdr:cxnSp macro=\"\"><xdr:nvCxnSpPr><xdr:cNvPr id=\"\(id)\" name=\"\(n)\"/><xdr:cNvCxnSpPr/></xdr:nvCxnSpPr>"
                + "<xdr:spPr>\(sp)</xdr:spPr></xdr:cxnSp>"
        }
        var body = ""
        for p in paragraphs.isEmpty ? [ShapeParagraph()] : paragraphs {
            body += "<a:p><a:pPr algn=\"\(p.align)\"/>"
            for r in p.runs {
                var attrs = " lang=\"en-US\" sz=\"\(Int((r.size * 100).rounded()))\""
                if r.bold { attrs += " b=\"1\"" }
                if r.italic { attrs += " i=\"1\"" }
                if r.underline { attrs += " u=\"sng\"" }
                let col = (r.color ?? textColor).map { "<a:solidFill><a:srgbClr val=\"\(rgb($0))\"/></a:solidFill>" } ?? ""
                body += "<a:r><a:rPr\(attrs)>\(col)</a:rPr><a:t>\(Xlsx._esc(r.text))</a:t></a:r>"
            }
            body += "<a:endParaRPr lang=\"en-US\" sz=\"\(Int(((p.endSize ?? 11) * 100).rounded()))\"/></a:p>"
        }
        return "<xdr:sp macro=\"\" textlink=\"\"><xdr:nvSpPr><xdr:cNvPr id=\"\(id)\" name=\"\(n)\"/><xdr:cNvSpPr\(textBox ? " txBox=\"1\"" : "")/></xdr:nvSpPr>"
            + "<xdr:spPr>\(sp)</xdr:spPr><xdr:txBody><a:bodyPr vertOverflow=\"clip\" horzOverflow=\"clip\" wrap=\"square\" rtlCol=\"0\" anchor=\"\(anchor)\"/>"
            + "<a:lstStyle/>\(body)</xdr:txBody></xdr:sp>"
    }
}

extension WorkbookController {
    /// Insert → Shapes: the shape at the active cell's corner, selected. A line is one point tall.
    @discardableResult
    func insertShape(_ p: ShapePreset, textBox: Bool = false) -> Bool {
        let ws = sheet
        let corner = ws.point(SheetMarker(col: active.col, colOff: 0, row: active.row, rowOff: 0))
        let (w, h): (Double, Double) = p.isLine ? (120, 1) : textBox ? (130, 40) : (110, 70)
        // A new shape that would land exactly on an earlier one steps down and right, so none hides another.
        var step = 0.0
        var anchor = ws.anchor(x: corner.x, y: corner.y, width: w, height: h)
        while ws.drawings.contains(where: { $0.anchor == anchor }) && step < 600 {
            step += 18
            anchor = ws.anchor(x: corner.x + step, y: corner.y + step, width: w, height: h)
        }
        let count = ws.drawings.filter { if case .shape = $0.kind { return true }; return false }.count + 1
        let name = (textBox ? "TextBox " : p.isLine ? "Straight Connector " : "Shape ") + "\(count)"
        var d = SheetDrawing(name: name, anchor: anchor, kind: .shape(SheetShape.made(p, textBox: textBox)))
        d.textBox = textBox
        structural {
            ws.drawings.append(d)
            ws.drawingsEdited = true
        }
        selectedDrawing = ws.drawings.count - 1
        _notify(selectionOnly: true)
        return true
    }

    /// The words of a shape (one undo step). A file's shape keeps its body properties and the first run's look.
    func setShapeText(_ index: Int, _ text: String) {
        let ws = sheet
        guard ws.drawings.indices.contains(index), ws.drawings[index].raw == nil || ws.drawings[index].rawText != nil,
              case .shape(var s) = ws.drawings[index].kind, !s.isGroup, s.plainText != text else { return }
        if s.paragraphs.isEmpty { s.paragraphs = [ShapeParagraph(align: s.anchor == "ctr" ? "ctr" : "l", runs: [ShapeRun(text: "", size: 11)])] }
        s.setPlainText(text)
        structural {
            ws.drawings[index].kind = .shape(s)
            ws.drawingsEdited = true
        }
    }
}
