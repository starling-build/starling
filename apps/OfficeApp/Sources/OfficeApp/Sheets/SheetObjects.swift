// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// What a sheet holds besides cells and drawings: embedded objects (a PDF,
// another workbook, a package), ActiveX controls and the classic form
// controls. None of them is in the drawing part. The sheet lists them
// (`oleObjects`, `controls`), each with a shape id; where it sits and what
// it shows is on that entry (Excel 2010 and later: an anchor in cells and
// a picture) or in the legacy VML drawing's shape of that id (an anchor in
// pixels, the picture, a form control's caption).
//
// An embedded object and an ActiveX control come with the picture Excel
// last drew of them, usually an EMF, and that picture is what Excel shows
// and prints. A form control has none: it is a kind (check box, option
// button, button…), a state and a caption, drawn here as Excel draws it.
//
// For display only. The sheet's elements and the parts behind them are
// kept as the file had them (`Worksheet.keptElements`), so nothing here is
// written, moved or selected.

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

struct SheetObject: Equatable {
    enum Kind: Equatable {
        /// The media part's path (the decode cache's key) and its bytes.
        case preview(path: String, data: Data)
        case control(FormControl)
    }
    var anchor: SheetAnchor
    var kind: Kind
    /// Shown on screen and left off paper (`x:PrintObject` False — what
    /// Excel gives a button unless told otherwise).
    var screenOnly = false
    /// The legacy shape's own outline, which Excel rules round the picture
    /// of an embedded object.
    var framed = false
}

/// A classic form control, as much of it as shows.
struct FormControl: Equatable {
    enum Kind: String { case checkBox, radio, button, label, groupBox, drop, list, scroll, spin, editBox }
    var kind: Kind
    var text = ""
    var checked = false
    /// `checked="Mixed"`: the grey third state.
    var mixed = false
    /// Its font, when the VML names one (twentieths of a point there).
    var fontSize: Double? = nil
    var fontFace: String? = nil
    var bold = false
    var italic = false
    var underline = false
    /// "Left", "Center", "Right" — the caption inside its room.
    var align = "Left"
    /// Flat, as on paper; a 3-D one has a sunken box.
    var flat = false
}

enum SheetObjectsXML {
    /// The objects and controls of one sheet.
    static func read(sheetPath: String, parts: [String: Data], sheet: XNode? = nil) -> [SheetObject] {
        guard let sheet = sheet ?? parts[sheetPath].flatMap({ XNode.parse($0) }) else { return [] }
        let lists = ["oleObjects", "controls"].compactMap { sheet.child($0) }
        guard !lists.isEmpty || sheet.child("legacyDrawing") != nil else { return [] }
        let rels = SheetDrawingsXML._relTargets(parts, of: sheetPath)
        // The legacy drawing's shapes, by id.
        var shapes: [String: _VmlShape] = [:]
        var vmlRels: [String: String] = [:]
        if let rid = sheet.child("legacyDrawing")?["r:id"], let path = rels[rid], let data = parts[path] {
            shapes = _vmlShapes(String(decoding: data, as: UTF8.self))
            vmlRels = SheetDrawingsXML._relTargets(parts, of: path)
        }
        var out: [SheetObject] = []
        var seen: Set<String> = []
        for list in lists {
            // An entry is there twice — the newer spelling under mc:Choice,
            // the older under mc:Fallback — and the one met first wins.
            var entries: [XNode] = []
            func walk(_ n: XNode) {
                for c in n.children {
                    let name = c.name.split(separator: ":").last.map(String.init) ?? c.name
                    if name == "oleObject" || name == "control" { entries.append(c) } else { walk(c) }
                }
            }
            walk(list)
            for e in entries {
                guard let id = e["shapeId"], !seen.contains(id) else { continue }
                seen.insert(id)
                let pr = e.child("objectPr") ?? e.child("controlPr")
                let shape = shapes[id]
                var anchor: SheetAnchor? = nil
                if let a = pr?.child("anchor"), let from = a.child("from").flatMap(SheetDrawingsXML._marker),
                   let to = a.child("to").flatMap(SheetDrawingsXML._marker) {
                    anchor = .twoCell(from: from, to: to)
                }
                guard let anchor = anchor ?? shape?.anchor else { continue }
                if shape?.hidden == true { continue }
                // A form control: its properties part says which, and how it stands.
                if let target = e["r:id"].flatMap({ rels[$0] }), let props = parts[target].flatMap({ XNode.parse($0) }),
                   props.name.hasSuffix("formControlPr"), let control = _control(props, shape: shape) {
                    out.append(SheetObject(anchor: anchor, kind: .control(control), screenOnly: shape?.printed == false || pr?["print"] == "0"))
                    continue
                }
                // Anything else shows its picture.
                let picture = pr?["r:id"].flatMap { rels[$0] } ?? shape?.imageRel.flatMap { vmlRels[$0] }
                if let picture, let data = parts[picture] {
                    out.append(SheetObject(anchor: anchor, kind: .preview(path: picture, data: data),
                                           screenOnly: shape?.printed == false || pr?["print"] == "0",
                                           framed: list.name.hasSuffix("oleObjects") && shape?.stroked == true))
                }
            }
        }
        // A form control from before Excel 2010 is in the legacy drawing and
        // nowhere else: no entry on the sheet, no properties part.
        for (id, shape) in shapes.sorted(by: { $0.key < $1.key }) where !seen.contains(id) && !shape.hidden {
            guard let anchor = shape.anchor, let kind = _kinds[shape.objectType.lowercased()] else { continue }
            var c = FormControl(kind: kind)
            c.checked = shape.checked == 1
            c.mixed = shape.checked == 2
            _caption(&c, shape)
            out.append(SheetObject(anchor: anchor, kind: .control(c), screenOnly: !shape.printed))
        }
        return out
    }

    private static let _kinds: [String: FormControl.Kind] = [
        "checkbox": .checkBox, "radio": .radio, "button": .button, "label": .label, "gbox": .groupBox,
        "drop": .drop, "list": .list, "scroll": .scroll, "spin": .spin, "editbox": .editBox,
    ]

    private static func _caption(_ c: inout FormControl, _ s: _VmlShape) {
        c.text = s.text
        c.fontSize = s.fontSize; c.fontFace = s.fontFace
        c.bold = s.bold; c.italic = s.italic; c.underline = s.underline
        if let a = s.align { c.align = a }
    }

    private static func _control(_ props: XNode, shape: _VmlShape?) -> FormControl? {
        guard let kind = _kinds[(props["objectType"] ?? "").lowercased()] else { return nil }
        var c = FormControl(kind: kind)
        c.checked = props["checked"] == "Checked"
        c.mixed = props["checked"] == "Mixed"
        c.flat = props["noThreeD"] == "1" || props["noThreeD"] == "true"
        if let s = shape { _caption(&c, s) }
        return c
    }

    // MARK: - The legacy drawing

    struct _VmlShape {
        var anchor: SheetAnchor? = nil
        var imageRel: String? = nil
        var text = ""
        var fontSize: Double? = nil
        var fontFace: String? = nil
        var bold = false, italic = false, underline = false
        var align: String? = nil
        var hidden = false
        /// `x:ClientData@ObjectType` ("Checkbox", "Note", "Pict"…) and
        /// `x:Checked` (1, or 2 for mixed).
        var objectType = ""
        var checked = 0
        var printed = true
        var stroked = true
    }

    /// The shapes of a VML drawing by their number (`_x0000_s1025` is 1025).
    /// VML is read as text: Excel's is XML, other writers' is not always.
    static func _vmlShapes(_ vml: String) -> [String: _VmlShape] {
        var out: [String: _VmlShape] = [:]
        // Groups, where shapes inside give their place in the group's own
        // coordinates (coordorigin, coordsize) over the group's box in points.
        var groups: [(range: Range<String.Index>, x: Double, y: Double, w: Double, h: Double, ox: Double, oy: Double, cw: Double, ch: Double)] = []
        var at = vml.startIndex
        while let g = vml[at...].firstRange(of: "<v:group ") {
            let tagEnd = vml[g.upperBound...].firstIndex(of: ">") ?? vml.endIndex
            let tag = vml[g.upperBound ..< tagEnd]
            let end = vml[tagEnd...].firstRange(of: "</v:group>")?.upperBound ?? vml.endIndex
            let style = _attr(tag, "style") ?? ""
            func pair(_ name: String) -> (Double, Double)? {
                let v = (_attr(tag, name) ?? "").split(separator: ",").compactMap { Double($0.trimmingWhitespace()) }
                return v.count == 2 ? (v[0], v[1]) : nil
            }
            if let x = _css(style, "margin-left"), let y = _css(style, "margin-top"), let w = _css(style, "width"), let h = _css(style, "height") {
                let o = pair("coordorigin") ?? (0, 0), c = pair("coordsize") ?? (w, h)
                if c.0 > 0, c.1 > 0 { groups.append((g.lowerBound ..< end, x, y, w, h, o.0, o.1, c.0, c.1)) }
            }
            at = tagEnd
        }
        var rest = Substring(vml)
        while let start = rest.firstRange(of: "<v:shape ") {
            let after = rest[start.upperBound...]
            let end = after.firstRange(of: "</v:shape>")?.lowerBound ?? after.endIndex
            let body = after[..<end]
            rest = after[end...]
            // (An ActiveX control's shape is named for the control, its number in o:spid.)
            let tagEnd = body.firstIndex(of: ">") ?? body.endIndex
            guard let id = _attr(body[..<tagEnd], "o:spid") ?? _attr(body[..<tagEnd], "id"),
                  let s = id.ranges(of: "_s").last else { continue }
            var shape = _VmlShape()
            if let v = _attr(body[..<tagEnd], "stroked") { shape.stroked = !["f", "false"].contains(v.lowercased()) }
            let style = _attr(body[..<tagEnd], "style") ?? ""
            shape.hidden = style.replacingAll(" ", with: "").containsSubstring("visibility:hidden")
            if let a = _between(body, "<x:Anchor>", "</x:Anchor>") {
                // Left column, its offset, top row, its offset, then the far
                // corner the same way; the offsets are screen pixels.
                let n = a.split(separator: ",").compactMap { Double($0.trimmingWhitespace()) }
                if n.count == 8 {
                    shape.anchor = .twoCell(from: SheetMarker(col: Int(n[0]), colOff: n[1] * 0.75, row: Int(n[2]), rowOff: n[3] * 0.75),
                                            to: SheetMarker(col: Int(n[4]), colOff: n[5] * 0.75, row: Int(n[6]), rowOff: n[7] * 0.75))
                }
            } else if let g = groups.first(where: { $0.range.contains(start.lowerBound) }),
                      let l = _css(style, "left"), let t = _css(style, "top"), let w = _css(style, "width"), let h = _css(style, "height") {
                // No cells to hold it: its place in its group, in points
                // (45540_form_Header's industry check boxes, a group of 28).
                let sx = g.w / g.cw, sy = g.h / g.ch
                shape.anchor = .absolute(x: g.x + (l - g.ox) * sx, y: g.y + (t - g.oy) * sy, width: w * sx, height: h * sy)
            } else if let x = _css(style, "margin-left"), let y = _css(style, "margin-top"), let w = _css(style, "width"), let h = _css(style, "height") {
                shape.anchor = .absolute(x: x, y: y, width: w, height: h)
            }
            if let image = body.firstRange(of: "<v:imagedata ") {
                let tag = body[image.upperBound...]
                shape.imageRel = _attr(tag, "o:relid") ?? _attr(tag, "r:id")
            }
            if let box = body.firstRange(of: "<v:textbox"), let close = body[box.upperBound...].firstRange(of: "</v:textbox>") {
                let inner = body[box.upperBound ..< close.lowerBound]
                let content = inner[(inner.firstIndex(of: ">").map { inner.index(after: $0) } ?? inner.startIndex)...]
                shape.text = _plain(content)
                if let font = content.firstRange(of: "<font ") {
                    let tag = content[font.upperBound...]
                    let tagClose = tag.firstIndex(of: ">") ?? tag.endIndex
                    shape.fontFace = _attr(tag[..<tagClose], "face")
                    shape.fontSize = _attr(tag[..<tagClose], "size").flatMap { Double($0) }.map { $0 / 20 }
                }
                shape.bold = content.containsSubstring("<b>"); shape.italic = content.containsSubstring("<i>"); shape.underline = content.containsSubstring("<u>")
                if let div = content.firstRange(of: "text-align:") {
                    let v = content[div.upperBound...].prefix { $0.isLetter }
                    shape.align = v.prefix(1).uppercased() + v.dropFirst().lowercased()
                }
            }
            if let data = body.firstRange(of: "<x:ClientData ") { shape.objectType = _attr(body[data.upperBound...], "ObjectType") ?? "" }
            if let p = _between(body, "<x:PrintObject>", "</x:PrintObject>") {
                shape.printed = !["false", "f", "0"].contains(p.trimmingWhitespace().lowercased())
            }
            shape.checked = _between(body, "<x:Checked>", "</x:Checked>").flatMap { Int($0.trimmingWhitespace()) } ?? 0
            if let h = _between(body, "<x:TextHAlign>", "</x:TextHAlign>") { shape.align = h.trimmingWhitespace() }
            out[String(id[s.upperBound...])] = shape
        }
        return out
    }

    /// A length in a VML style (`margin-left:7.5pt`, `left:9`): points,
    /// or a bare number (a group's own units, which its caller scales).
    private static func _css(_ style: String, _ key: String) -> Double? {
        for part in style.split(separator: ";") {
            let kv = part.split(separator: ":", maxSplits: 1).map { $0.trimmingWhitespace() }
            guard kv.count == 2, kv[0].lowercased() == key else { continue }
            var v = kv[1].lowercased()
            var k = 1.0
            if v.hasSuffix("pt") { v.removeLast(2) } else if v.hasSuffix("px") { v.removeLast(2); k = 0.75 }
            else if v.hasSuffix("in") { v.removeLast(2); k = 72 }
            return Double(v).map { $0 * k }
        }
        return nil
    }

    /// `name="value"` or `name='value'` in a run of tag text.
    private static func _attr(_ s: Substring, _ name: String) -> String? {
        var from = s.startIndex
        while let r = s[from...].firstRange(of: name + "=") {
            // (Not the tail of a longer name: `id=` in `spid=`.)
            let boundary = r.lowerBound == s.startIndex || !(s[s.index(before: r.lowerBound)].isLetter || s[s.index(before: r.lowerBound)] == ":")
            let rest = s[r.upperBound...]
            if boundary, let q = rest.first, q == "\"" || q == "'" {
                let body = rest.dropFirst()
                return String(body[..<(body.firstIndex(of: q) ?? body.endIndex)])
            }
            from = r.upperBound
        }
        return nil
    }

    private static func _between(_ s: Substring, _ open: String, _ close: String) -> String? {
        guard let a = s.firstRange(of: open), let b = s[a.upperBound...].firstRange(of: close) else { return nil }
        return String(s[a.upperBound ..< b.lowerBound])
    }

    /// Markup's text: tags dropped, the usual entities read, space folded.
    private static func _plain(_ s: Substring) -> String {
        var out = "", inTag = false
        for ch in s {
            if ch == "<" { inTag = true } else if ch == ">" { inTag = false } else if !inTag { out.append(ch) }
        }
        for (entity, ch) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&#10;", " ")] {
            out = out.replacingAll(entity, with: ch)
        }
        return out.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }
}

// MARK: - Drawing a form control

extension FormControl {
    /// The control in `r`, at `pt` pixels per point. Excel's own drawing of
    /// each, as it prints them: a small box or ring at the left with the
    /// caption beside it, a grey button face, a ruled group.
    func paint(_ canvas: any Canvas, in r: Rect, pt: Double) {
        let ink = Color(0xFF000000), edge = Color(0xFF333333)
        let line = Paint()
        line.style = .stroke
        line.strokeWidth = max(0.5, 0.6 * pt)
        line.color = edge
        let fill = Paint()
        fill.style = .fill
        var style = GridTextStyle(family: OfficeFonts.drawn(fontFace ?? "Segoe UI"), size: (fontSize ?? 9) * pt, color: Int64(ink.value))
        style.bold = bold; style.italic = italic; style.underline = underline
        func caption(in room: Rect, align: String, clip: Bool = true) {
            guard !text.isEmpty, room.width > 1 else { return }
            let tp = TextPainter(text: TextSpan(text: text, style: style.flutter), textAlign: .left, textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: .infinity)
            let x = align == "Right" ? room.right - tp.width : align == "Center" ? room.left + (room.width - tp.width) / 2 : room.left
            canvas.save()
            if clip { canvas.clipRect(r) }
            tp.paint(canvas, Offset(x, room.top + (room.height - tp.height) / 2))
            canvas.restore()
            tp.dispose()
        }
        switch kind {
        case .checkBox, .radio:
            let side = 4.6 * pt
            let mark = Rect.fromLTWH(r.left + 2 * pt, r.top + (r.height - side) / 2, side, side)
            fill.color = Color(0xFFFFFFFF)
            if kind == .radio {
                canvas.drawOval(mark, fill)
                canvas.drawOval(mark, line)
                if checked { fill.color = ink; canvas.drawOval(mark.deflate(side * 0.24), fill) }
            } else {
                if mixed { fill.color = Color(0xFFC0C0C0) }
                canvas.drawRect(mark, fill)
                canvas.drawRect(mark, line)
                if checked || mixed {
                    let tick = Path()
                    tick.moveTo(mark.left + side * 0.2, mark.top + side * 0.52)
                    tick.lineTo(mark.left + side * 0.42, mark.top + side * 0.76)
                    tick.lineTo(mark.left + side * 0.82, mark.top + side * 0.24)
                    let p = Paint()
                    p.style = .stroke
                    p.strokeWidth = max(0.6, 0.8 * pt)
                    p.color = ink
                    canvas.drawPath(tick, p)
                }
            }
            caption(in: Rect.fromLTRB(mark.right + 4 * pt, r.top, r.right - pt, r.bottom), align: align)
        case .button:
            fill.color = Color(0xFFF0F0F0)
            canvas.drawRect(r, fill)
            line.color = Color(0xFF707070)
            canvas.drawRect(r.deflate(line.strokeWidth / 2), line)
            caption(in: r, align: "Center")
        case .label:
            caption(in: Rect.fromLTRB(r.left + pt, r.top, r.right - pt, r.bottom), align: align)
        case .groupBox:
            // The rule runs through the caption's middle and breaks for it.
            let top = r.top + style.size * 0.6
            line.color = Color(0xFFA0A0A0)
            canvas.drawRect(Rect.fromLTRB(r.left + 0.5, top, r.right - 0.5, r.bottom - 0.5), line)
            if !text.isEmpty {
                let tp = TextPainter(text: TextSpan(text: text, style: style.flutter), textAlign: .left, textDirection: .ltr)
                tp.layout(minWidth: 0, maxWidth: .infinity)
                fill.color = Color(0xFFFFFFFF)
                canvas.drawRect(Rect.fromLTWH(r.left + 5 * pt, r.top, tp.width + 4 * pt, tp.height), fill)
                tp.paint(canvas, Offset(r.left + 7 * pt, r.top))
                tp.dispose()
            }
        case .drop, .list, .editBox:
            fill.color = Color(0xFFFFFFFF)
            canvas.drawRect(r, fill)
            line.color = Color(0xFF707070)
            canvas.drawRect(r.deflate(line.strokeWidth / 2), line)
            if kind != .editBox { _arrows(canvas, in: Rect.fromLTRB(max(r.left, r.right - 12 * pt), r.top, r.right, r.bottom),
                                          vertical: true, both: kind == .list, pt: pt) }
        case .scroll, .spin:
            _arrows(canvas, in: r, vertical: r.height >= r.width, both: true, pt: pt)
        }
    }

    /// A scroll bar's or a drop-down's buttons: a grey strip with an arrow at
    /// each end (or one, in the middle).
    private func _arrows(_ canvas: any Canvas, in r: Rect, vertical: Bool, both: Bool, pt: Double) {
        let fill = Paint()
        fill.style = .fill
        fill.color = Color(0xFFF0F0F0)
        canvas.drawRect(r, fill)
        let line = Paint()
        line.style = .stroke
        line.strokeWidth = max(0.5, 0.6 * pt)
        line.color = Color(0xFF707070)
        canvas.drawRect(r.deflate(line.strokeWidth / 2), line)
        fill.color = Color(0xFF404040)
        let a = min(r.width, r.height, 8 * pt) * 0.3
        func arrow(_ c: Offset, _ dx: Double, _ dy: Double) {
            // Pointing along (dx, dy), its base across it.
            let p = Path()
            p.moveTo(c.dx + dx * a, c.dy + dy * a)
            p.lineTo(c.dx - dx * a * 0.6 - dy * a, c.dy - dy * a * 0.6 + dx * a)
            p.lineTo(c.dx - dx * a * 0.6 + dy * a, c.dy - dy * a * 0.6 - dx * a)
            p.close()
            canvas.drawPath(p, fill)
        }
        let inset = min(r.width, r.height) / 2
        if !both {
            arrow(r.center, 0, 1)
        } else if vertical {
            arrow(Offset(r.center.dx, r.top + inset), 0, -1); arrow(Offset(r.center.dx, r.bottom - inset), 0, 1)
        } else {
            arrow(Offset(r.left + inset, r.center.dy), -1, 0); arrow(Offset(r.right - inset, r.center.dy), 1, 0)
        }
    }
}
