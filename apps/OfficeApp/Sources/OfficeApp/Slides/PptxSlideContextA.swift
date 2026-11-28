// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

extension SlideContext {

    /// A connector's glued ends (`a:stCxn`, `a:endCxn`), by the file's shape ids; PptxReader turns them into deck ids.
    static func readConns(_ el: XNode, into st: inout ShapeState) {
        let c = el.first("p:nvCxnSpPr")?.first("p:cNvCxnSpPr")
        func conn(_ n: XNode?) -> ShapeConn? {
            guard let n, let id = n["id"].flatMap(Int.init), let idx = n["idx"].flatMap(Int.init) else { return nil }
            return ShapeConn(shape: id, site: idx)
        }
        st.pendingConnStart = conn(c?.first("a:stCxn"))
        st.pendingConnEnd = conn(c?.first("a:endCxn"))
    }

    func _connector(_ el: XNode, _ transform: ((Rect) -> Rect)?, id: () -> Int) -> ShapeState? {
        guard let x = el.first("p:spPr")?.first("a:xfrm"), var box = _xfrmRect(x) else { return nil }
        if let t = transform { box = t(box) }
        // An elbow or a curve: its own path in its box, turned and mirrored
        // as a shape is (tdf141058's tree, whose elbows were diagonals).
        let prst = el.first("p:spPr")?.first("a:prstGeom")?["prst"] ?? "line"
        if prst.hasPrefix("bentConnector") || prst.hasPrefix("curvedConnector"),
           let g = PresetGeometry.geometry(prst, width: box.width * Pptx.emu, height: box.height * Pptx.emu,
                                           adjustments: PresetGeometry.adjustments(el.first("p:spPr")?.first("a:prstGeom"))) {
            let ln = el.first("p:spPr")?.first("a:ln")
            let color = ln?.has("a:noFill") == true ? nil : ln?.first("a:solidFill").flatMap(colors.color(in:))
                ?? el.first("p:style")?.first("a:lnRef").flatMap(colors.lineColor(in:)) ?? colors.scheme("tx1")
            var width = ln?["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? 0.75
            if ln?["w"] == nil, let idx = el.first("p:style")?.first("a:lnRef")?["idx"].flatMap(Int.init),
               theme.lineWidths.indices.contains(idx - 1) { width = theme.lineWidths[idx - 1] }
            var st = ShapeState(id: id(), name: el.first("p:nvCxnSpPr")?.first("p:cNvPr")?["name"] ?? "Connector",
                                kind: .geometry(ShapePreset(rawValue: prst)), frame: box,
                                rotation: (x["rot"].flatMap(Double.init) ?? 0) / 60000, fill: nil, outline: color,
                                outlineWidth: width, anchor: .middle, insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                                prompt: nil, text: nil, font: nil, size: 18, color: Color(0xFF000000), listIndent: 18)
            st.flipH = x["flipH"] == "1"
            st.flipV = x["flipV"] == "1"
            st.customPath = g
            st.adjusts = PresetGeometry.adjustments(el.first("p:spPr")?.first("a:prstGeom"))
            st.sourceXML = PptxXML.serialize(el)
            st.sourcePart = part
            st.keptLine = KeptLine(line: box, box: box, outline: color, width: width)
            st.keptLine?.rotation = st.rotation; st.keptLine?.flipH = st.flipH; st.keptLine?.flipV = st.flipV
            st.keptLine?.adjusts = st.adjusts
            st.outlineDash = PptxReader.dash(ln)
            st.outlineJoin = PptxReader.join(ln)
            st.outlineCap = ln?["cap"]
            st.headEnd = PptxReader.lineEnd(ln?.first("a:headEnd"))
            st.tailEnd = PptxReader.lineEnd(ln?.first("a:tailEnd"))
            st.keptLine?.dash = st.outlineDash; st.keptLine?.head = st.headEnd; st.keptLine?.tail = st.tailEnd
            st.shadow = _shapeShadow(el.first("p:spPr"), el.first("p:style"))
            Self.readConns(el, into: &st)
            return st
        }
        // Flips turn the box's diagonal into the line's direction, and the
        // rotation turns both ends about the box's centre.
        var x1 = box.left, x2 = box.right, y1 = box.top, y2 = box.bottom
        if x["flipH"] == "1" { swap(&x1, &x2) }
        if x["flipV"] == "1" { swap(&y1, &y2) }
        var a = Offset(x1, y1), b = Offset(x2, y2)
        if let rot = x["rot"].flatMap(Double.init), rot != 0 {
            let r = rot / 60000 * .pi / 180, c = box.center
            func turn(_ p: Offset) -> Offset {
                let dx = p.dx - c.dx, dy = p.dy - c.dy
                return Offset(c.dx + dx * cos(r) - dy * sin(r), c.dy + dx * sin(r) + dy * cos(r))
            }
            a = turn(a); b = turn(b)
        }
        let frame = Rect.fromLTRB(a.dx, a.dy, b.dx, b.dy)
        let ln = el.first("p:spPr")?.first("a:ln")
        let color = ln?.first("a:solidFill").flatMap(colors.color(in:))
            ?? el.first("p:style")?.first("a:lnRef").flatMap(colors.lineColor(in:)) ?? colors.scheme("tx1")
        // (Its width the theme's line style, where it names one and says
        // none of its own, as an elbow's: lineStyle's `lnRef idx="2"`, 2 pt
        // in PowerPoint's print, drawn at 0.75.)
        var width = ln?["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? 0.75
        if ln?["w"] == nil, let idx = el.first("p:style")?.first("a:lnRef")?["idx"].flatMap(Int.init),
           theme.lineWidths.indices.contains(idx - 1) { width = theme.lineWidths[idx - 1] }
        var st = ShapeState(id: id(), name: el.first("p:nvCxnSpPr")?.first("p:cNvPr")?["name"] ?? "Line",
                            kind: .geometry(.line), frame: frame, rotation: 0, fill: nil, outline: color,
                            outlineWidth: width,
                            anchor: .middle, insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil,
                            text: nil, font: nil, size: 18, color: Color(0xFF000000), listIndent: 18)
        st.sourceXML = PptxXML.serialize(el)
        st.sourcePart = part
        st.keptLine = KeptLine(line: frame, box: box, outline: color, width: width)
        st.shadow = _shapeShadow(el.first("p:spPr"), el.first("p:style"))
        st.outlineDash = PptxReader.dash(el.first("p:spPr")?.first("a:ln"))
        st.outlineJoin = PptxReader.join(el.first("p:spPr")?.first("a:ln"))
        st.outlineCap = el.first("p:spPr")?.first("a:ln")?["cap"]
        st.headEnd = PptxReader.lineEnd(ln?.first("a:headEnd"))
        st.tailEnd = PptxReader.lineEnd(ln?.first("a:tailEnd"))
        st.keptLine?.dash = st.outlineDash; st.keptLine?.head = st.headEnd; st.keptLine?.tail = st.tailEnd
        Self.readConns(el, into: &st)
        return st
    }

    /// The picture a legacy VML drawing shows for shape `spid`
    /// (`<v:shape id="…"><v:imagedata o:relid="…"/>`): what an embedded
    /// object written before `p:pic` fallbacks displays. The drawing is
    /// read as text — VML is not always well-formed XML.
    func _vmlImage(_ spid: String) -> ImageAttachment? {
        // (Office 2007 names the relationship `legacyDrawing`, under its
        // own namespace: tdf169781's budget chart.)
        for rel in package.rels(part) where ["vmlDrawing", "legacyDrawing"].contains(rel.kind) && !rel.external {
            guard let data = package.parts[rel.target], let vml = String(data: data, encoding: .utf8),
                  let shape = vml.rangeOfSubstring("id=\"\(spid)\""),
                  let end = vml.rangeOfSubstring("</v:shape>", in: shape.upperBound ..< vml.endIndex) else { continue }
            let body = vml[shape.upperBound ..< end.lowerBound]
            for key in ["o:relid=\"", "r:id=\"", "r:pict=\""] {
                guard let at = String(body).rangeOfSubstring(key) else { continue }
                let rest = String(body)[at.upperBound...]
                guard let close = rest.firstIndex(of: "\"") else { continue }
                let rid = String(rest[..<close])
                if let target = package.rels(rel.target).first(where: { $0.id == rid }), !target.external,
                   package.parts[target.target] != nil {
                    return images.attachment(target.target, package)
                }
            }
        }
        return nil
    }

    /// PowerPoint's box for a picture it cannot draw: white, ruled black,
    /// a bevelled icon with a red cross 7 pt in, and "The picture can't be
    /// displayed." in Segoe UI 10.5 pt, 27 pt in — measured on its print.
    static func brokenPicture(in r: Rect, onMaster: Bool = false, id: () -> Int) -> [ShapeState] {
        func box(_ f: Rect, fill: Color?, outline: Color? = nil, width: Double = 0, preset: String = "rect") -> ShapeState {
            ShapeState(id: id(), name: "Broken picture", kind: .geometry(ShapePreset(rawValue: preset)), frame: f, rotation: 0,
                       fill: fill, outline: outline, outlineWidth: width, anchor: .top,
                       insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil, text: nil,
                       font: nil, size: 18, color: Color(0xFF000000), listIndent: 18)
        }
        if onMaster {
            // On a master or layout PowerPoint prints the same box at a seventh
            // of the size (tdf147586): a hairline frame, a speck of icon, and the
            // message as a black bar 16.6 x 1.1 pt.
            return [box(r, fill: Color(0xFFFFFFFF), outline: Color(0xFF000000), width: 0.14),
                    box(Rect.fromLTWH(r.left + 3.4, r.top + 1.2, 16.6, 1.1), fill: Color(0xFF000000))]
        }
        var shapes = [box(Rect.fromLTRB(r.left + 0.5, r.top + 0.5, r.right - 0.5, r.bottom - 0.5),
                          fill: Color(0xFFFFFFFF), outline: Color(0xFF000000), width: 1)]
        let x = r.left + 7, y = r.top + 7
        shapes.append(box(Rect.fromLTWH(x, y, 14, 16), fill: Color(0xFF000000)))
        shapes.append(box(Rect.fromLTWH(x, y, 13, 15), fill: Color(0xFF808080)))
        shapes.append(box(Rect.fromLTWH(x + 1, y + 1, 12, 14), fill: Color(0xFFC0C0C0)))
        shapes.append(box(Rect.fromLTWH(x + 1, y + 1, 11, 13), fill: Color(0xFFFFFFFF)))
        var a = box(Rect.fromLTWH(x + 4.5, y + 5.5, 5, 4), fill: nil, outline: Color(0xFFFF0000), width: 1.3, preset: "line")
        shapes.append(a)
        a.id = id()
        a.flipV = true
        shapes.append(a)
        var text = box(Rect.fromLTRB(r.left + 27, r.top + 8.0, max(r.left + 28, r.right - 4), r.bottom), fill: nil)
        text.kind = .textBox
        let message = "The picture can't be displayed."
        let look = CharStyle(fontFamily: "Segoe UI", fontSize: 10.5, color: Color(0xFF000000))
        text.text = RichDocument(paragraphs: [RichParagraph(text: message, runs: [Run(length: message.utf16.count, style: look)],
                                                            style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0))])
        text.font = "Segoe UI"
        text.size = 10.5
        shapes.append(text)
        return shapes
    }

    func _picture(_ el: XNode, _ transform: ((Rect) -> Rect)?, id: () -> Int) -> ShapeState? {
        // Audio and video are a `p:pic` too — the poster frame, with the
        // media hung on `p:nvPr` (`a:audioFile`/`a:videoFile`, `p14:media`)
        // and a `p:timing` tree that plays it. Modelled as a picture, the
        // media relationships would be dropped under a timing tree that
        // still calls them, and PowerPoint repairs the slide. Kept whole.
        if let nv = el.first("p:nvPicPr")?.first("p:nvPr"),
           nv.children.contains(where: { ["a:audioFile", "a:videoFile", "a:quickTimeFile", "a:wavAudioFile"].contains($0.name) }) {
            // Drawn as its poster frame (the pic's own picture), or black
            // where it has none, as PowerPoint shows a video at rest.
            guard var o = _opaque(el, label: "Media", transform, id: id) else { return nil }
            if case .opaque(var obj) = o.kind {
                var poster = ShapeState(id: id(), name: "Poster", kind: .geometry(.rect), frame: o.frame, rotation: 0,
                                        fill: Color(0xFF000000), outline: nil, outlineWidth: 0, anchor: .top,
                                        insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil, text: nil,
                                        font: nil, size: 18, color: Color(0xFF000000), listIndent: 18)
                if let rid = el.first("p:blipFill")?.first("a:blip")?["r:embed"],
                   let target = package.rels(part).first(where: { $0.id == rid }), !target.external,
                   package.parts[target.target] != nil {
                    poster.kind = .picture(images.attachment(target.target, package))
                    poster.fill = nil
                }
                obj.rendering = [poster]
                o.kind = .opaque(obj)
                // The clip itself, so the show can play it: the embedded copy
                // (`p14:media r:embed`), else the one the pic links to.
                let embed = nv.descendants("p14:media").first?["r:embed"]
                let link = nv.children.first { ["a:audioFile", "a:videoFile", "a:quickTimeFile", "a:wavAudioFile"].contains($0.name) }?["r:link"]
                let isVideo = !nv.children.contains { $0.name == "a:audioFile" || $0.name == "a:wavAudioFile" }
                for rid in [embed, link].compactMap({ $0 }) {
                    guard let rel = package.rels(part).first(where: { $0.id == rid }), !rel.external,
                          let data = package.parts[rel.target] else { continue }
                    o.media = MediaClip(data: data, name: rel.target.lastPathComponent, isVideo: isVideo, existing: true)
                    break
                }
            }
            return o
        }
        // A picture in a placeholder (`p:ph`) may leave its frame to the
        // layout's (`<p:spPr/>`): the inherited placeholder says where.
        var own = el.first("p:spPr")?.first("a:xfrm").flatMap(_xfrmRect)
        if own == nil, let ph = _ph(el) {
            let inherited = _inherited(ph)
            for node in [inherited.layout, inherited.master] {
                if let x = node?.first("p:spPr")?.first("a:xfrm"), let r = _xfrmRect(x) { own = r; break }
            }
        }
        guard let rid = el.first("p:blipFill")?.first("a:blip")?["r:embed"],
              let target = package.rels(part).first(where: { $0.id == rid }), !target.external,
              package.parts[target.target] != nil,
              var frame = own else {
            guard var o = _opaque(el, label: "Picture", transform, id: id) else { return nil }
            // A picture that names no picture (no `blipFill`, or a blip with
            // neither `r:embed` nor `r:link`): PowerPoint's box saying so, as
            // its print has it in missing-blip-fill, tdf147586 and a fuzzed
            // deck. (Not one naming a part the package lacks: Divino's,
            // its zip cut short, print as nothing.)
            let blip = el.first("p:blipFill")?.first("a:blip")
            if blip?["r:embed"] == nil, blip?["r:link"] == nil, case .opaque(var obj) = o.kind {
                obj.rendering = Self.brokenPicture(in: o.frame, onMaster: part.containsSubstring("slideMasters/") || part.containsSubstring("slideLayouts/"), id: id)
                obj.clipsRendering = true
                o.kind = .opaque(obj)
            }
            return o
        }
        if let t = transform { frame = t(frame) }
        let image = images.attachment(target.target, package, blip: el.first("p:blipFill")?.first("a:blip"))
        let rotation = (el.first("p:spPr")?.first("a:xfrm")?["rot"].flatMap(Double.init) ?? 0) / 60000
        // The crop: fractions of the picture cut from each edge.
        var crop: EdgeInsets? = nil
        if let src = el.first("p:blipFill")?.first("a:srcRect") {
            func f(_ k: String) -> Double { (src[k].flatMap(Double.init) ?? 0) / 100000 }
            let c = EdgeInsets(left: f("l"), top: f("t"), right: f("r"), bottom: f("b"))
            if c != .zero { crop = c }
        }
        var s = ShapeState(id: id(), name: el.first("p:nvPicPr")?.first("p:cNvPr")?["name"] ?? "Picture",
                           kind: .picture(image), frame: frame, rotation: rotation, fill: nil, outline: nil,
                           outlineWidth: 0, anchor: .top, insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0),
                           prompt: nil, text: nil, font: nil, size: 18, color: Color(0xFF000000), listIndent: 18,
                           crop: crop)
        // Mirrored, and cropped to a shape (an ellipse, rounded corners).
        let xfrm = el.first("p:spPr")?.first("a:xfrm")
        s.flipH = xfrm?["flipH"] == "1"
        s.flipV = xfrm?["flipV"] == "1"
        s.aspectLock = el.first("p:nvPicPr")?.first("p:cNvPicPr")?.first("a:picLocks")?["noChangeAspect"] == "1"
        if let spPr = el.first("p:spPr") { s.scene3d = Extrusion.read(spPr, colors: colors) }
        if let prst = el.first("p:spPr")?.first("a:prstGeom")?["prst"], prst != "rect" {
            s.pictureGeometry = ShapePreset(rawValue: prst)
        } else if let geom = el.first("p:spPr")?.first("a:custGeom") {
            // Or to a freeform outline (tdf153008's circle in four curves).
            s.customPath = FreeformGeometry.parse(geom, width: frame.width * Pptx.emu, height: frame.height * Pptx.emu)
        }
        if let blip = el.first("p:blipFill")?.first("a:blip") {
            (s.pictureAlpha, s.pictureDuotone) = PptxReader.blipEffects(blip, colors: colors)
            s.pictureLevels = PptxReader.blipLevels(blip)
            if let l = blip.first("a:lum") {
                s.pictureBrightness = (l["bright"].flatMap(Double.init) ?? 0) / 100000
                s.pictureContrast = (l["contrast"].flatMap(Double.init) ?? 0) / 100000
            }
            if let change = blip.first("a:clrChange"), let from = change.first("a:clrFrom").flatMap({ colors.color(in: $0) }),
               let to = change.first("a:clrTo").flatMap({ colors.color(in: $0) }) {
                s.pictureColorChange = [from, to]
            }
        }
        if let b = el.first("p:blipFill") { s.pictureInset = PptxReader.stretchInset(b) }
        // Its outline (graphic-stroke's green frame round an OLE object's
        // picture): the line's own colour, else its style's.
        let ln = el.first("p:spPr")?.first("a:ln"), lnRef = el.first("p:style")?.first("a:lnRef")
        if ln?.has("a:noFill") != true {
            if let f = ln?.first("a:solidFill") { s.outline = colors.color(in: f) }
            else if let ref = lnRef, ref["idx"] != "0" { s.outline = colors.lineColor(in: ref) }
            if s.outline != nil {
                var w = 0.75
                if let idx = lnRef?["idx"].flatMap(Int.init), theme.lineWidths.indices.contains(idx - 1) { w = theme.lineWidths[idx - 1] }
                s.outlineWidth = ln?["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? w
                s.outlineDash = PptxReader.dash(ln)
            }
        }
        s.shadow = _shapeShadow(el.first("p:spPr"), el.first("p:style"))
        s.reflection = LevelStyle.reflection(el.first("p:spPr")?.first("a:effectLst"))
        // (Its edge faded as a shape's is: croppedTo0's rounded picture,
        // its 10 pt `softEdge` drawn sharp before. Not one in 3-D, a
        // bevel on it: tdf170095's prints whole, unfaded.)
        if el.first("p:spPr")?.first("a:sp3d") == nil,
           let soft = el.first("p:spPr")?.first("a:effectLst")?.first("a:softEdge")?["rad"].flatMap(Double.init), soft > 0 {
            s.softEdge = soft / Pptx.emu
        }
        if let g = el.first("p:spPr")?.first("a:effectLst")?.first("a:glow"), let c = colors.color(in: g) {
            s.glowRadius = (g["rad"].flatMap(Double.init) ?? 0) / Pptx.emu
            s.glowColor = c
        }
        // A fill of its own, behind the picture (showing through its
        // transparent parts and around one padded by a negative crop).
        if let pr = el.first("p:spPr") {
            if let f = pr.first("a:solidFill"), let c = colors.color(in: f) {
                s.fillStyle = SlideFill(color: c)
            } else if let g = pr.first("a:gradFill"), let gradient = PptxReader.gradient(g, colors: colors), gradient.stops.count >= 2 {
                s.fillStyle = gradient
            }
        }
        // The element too: written back while the picture is unchanged.
        s.sourceXML = PptxXML.serialize(el)
        s.sourcePart = part
        s.altText = el.descendant("p:cNvPr")?["descr"].flatMap { $0.isEmpty ? nil : $0 }
        s.keptPicture = KeptPicture(imageId: image.id, alt: s.altText, crop: crop, rotation: rotation, alpha: s.pictureAlpha,
                                    brightness: s.pictureBrightness, contrast: s.pictureContrast,
                                    geometry: s.pictureGeometry, freeform: s.customPath != nil, look: s.pictureLook)
        return s
    }

    /// An XML boolean attribute: "1" or "true" (444a89c2af21's merged cells say hMerge="true", which "1" alone left unmerged, a 354 pt cell laid out 18 pt wide).
    func _xmlOn(_ v: String?) -> Bool { v == "1" || v == "true" }

    /// `a:tbl` as an editable table: grid widths, merged cells (gridSpan,
    /// rowSpan; the hMerge/vMerge stand-ins dropped), cell text, and the
    /// look approximated from the table's flags in this deck's first accent.
    /// The element is kept too, written back while the text is unchanged.
    func _table(_ el: XNode, _ transform: ((Rect) -> Rect)?, id: () -> Int) -> ShapeState? {
        guard let tbl = el.descendant("a:tbl"), var frame = el.first("p:xfrm").flatMap(_xfrmRect) else { return nil }
        if let t = transform { frame = t(frame) }
        let tableId = UUID().uuidString
        // (A right-to-left table, `a:tblPr rtl="1"`, runs its columns from the right: its first column is the rightmost, as
        // PowerPoint prints rtl/cc66a30f p18's "نوع شکست".)
        let rtlTable = tbl.first("a:tblPr")?["rtl"] == "1"
        var widths = (tbl.first("a:tblGrid")?.all("a:gridCol") ?? []).compactMap { $0["w"].flatMap(Double.init).map { $0 / Pptx.emu } }
        if rtlTable { widths.reverse() }
        // A frame narrower than its columns (Google's export writes 3000000 EMU whatever the table is): PowerPoint draws the
        // grid, not the frame (e2a1fcdb p8 print: 908 pt wide on a 236 pt frame).
        let gridSum = widths.reduce(0, +)
        if gridSum > 0, frame.width > 0, frame.width < gridSum * 0.99 { frame = Rect.fromLTWH(frame.left, frame.top, gridSum, frame.height) }
        let pr = tbl.first("a:tblPr")
        let firstRow = pr?["firstRow"] == "1"
        let banded = pr?["bandRow"] == "1"
        let styleId = pr?.first("a:tableStyleId")?.text.trimmingWhitespace() ?? ""
        // No style id at all draws as "No Style, Table Grid" does.
        let plain = styleId.isEmpty || ["{2D5ABB26-0587-4C30-8999-92F81FD0307C}", "{5940675A-B579-460E-94D1-54222C63F5DA}"].contains(styleId)
        // A table's text takes the master's other-text style over the
        // presentation's default: tdf135843_insideH's empty rows are
        // 10.13 pt lines (the master's), not 13.5 (the default's).
        // (The deck's default line and paragraph spacing do not reach a table's cells: 65a1be73's defaults say 120% and
        // 20% before, its rows print at their stated height, 33.5 pt over 16 pt lines.)
        var fromDefaults = LevelStyle.paragraph(defaults?.first("a:lvl1pPr"), colors)
        fromDefaults.lineMultiple = nil; fromDefaults.linePoints = nil
        fromDefaults.beforePoints = nil; fromDefaults.beforePercent = nil
        fromDefaults.afterPoints = nil; fromDefaults.afterPercent = nil
        // (Nor does its bold: 9e09a947a0fd's defaults say b="1", yet a table's second column prints regular Arial; bold comes from the table style.)
        fromDefaults.bold = nil
        var base = LevelStyle.paragraph(master?.first("p:txStyles")?.first("p:otherStyle")?.first("a:lvl1pPr"), colors)
            .filled(from: fromDefaults)
        // The style the id names, when the deck defines it: the look of the
        // whole table, its header row, bands, and (when the table's flags
        // ask) its first and last columns and last row.
        let style = plain ? nil : tableStyles[styleId]
        let whole = style.flatMap { _tablePart($0, "a:wholeTbl") }
        let firstRowPart = firstRow ? style.flatMap { _tablePart($0, "a:firstRow") } : nil
        let lastRowPart = pr?["lastRow"] == "1" ? style.flatMap { _tablePart($0, "a:lastRow") } : nil
        let firstColPart = pr?["firstCol"] == "1" ? style.flatMap { _tablePart($0, "a:firstCol") } : nil
        let lastColPart = pr?["lastCol"] == "1" ? style.flatMap { _tablePart($0, "a:lastCol") } : nil
        if let c = whole?.textColor { base.color = c }
        // The table style's face over the deck's default text: every
        // built-in style names the theme's minor font (`fontRef idx=
        // "minor"`), so a table set in it where the deck's default text
        // says Arial — the AES deck's Verdana tables, which wrapped a
        // word or two later in Arial.
        base.font = whole?.font ?? (style == nil ? "+mn-lt" : base.font)
        let rowCount = tbl.all("a:tr").count
        var paragraphs: [RichParagraph] = []
        var cellListFormats: [String: [Int: ListLevelFormat]] = [:], cellListRestarts: [String: [Int: Int]] = [:]
        for (r, tr) in tbl.all("a:tr").enumerated() {
            var column = 0
            let cells = tr.all("a:tc")
            let columnCount = cells.count
            for (c, tc) in cells.enumerated() {
                defer { column += 1 }
                if _xmlOn(tc["hMerge"]) || _xmlOn(tc["vMerge"]) { continue }
                // A span reaches over the merged cells that follow it and no
                // further: LIBRE_OFFICE-100610's "Vermelho" says three
                // columns with none after it, and PowerPoint wraps it in one.
                var span = 1
                while span < (tc["gridSpan"].flatMap(Int.init) ?? 1), c + span < cells.count, _xmlOn(cells[c + span]["hMerge"]) { span += 1 }
                var cell = CellRef(table: tableId, row: r, column: rtlTable ? max(0, columnCount - column - span) : column,
                                   span: span, rowSpan: tc["rowSpan"].flatMap(Int.init) ?? 1)
                // The style's regional looks, the later ones over the earlier
                // (a corner cell of the header row looks like the header).
                var regional: [TablePartStyle] = []
                // Banded columns (`bandCol`): the style's two column bands
                // by turns, counted from the column after an emphasised
                // first one — table-with-different-font-colors' darker
                // second column and cyan third. Their fill is under the
                // row bands', which PowerPoint draws over them.
                var bandColPart: TablePartStyle? = nil
                if pr?["bandCol"] == "1", let style {
                    let k = c - (pr?["firstCol"] == "1" ? 1 : 0)
                    if k >= 0 { bandColPart = _tablePart(style, k % 2 == 0 ? "a:band1V" : "a:band2V") }
                }
                if let f = bandColPart?.fill, !banded, r > 0 || firstRowPart == nil { cell.fill = f }
                if c == 0, let p = firstColPart { regional.append(p) }
                if c == columnCount - 1, let p = lastColPart { regional.append(p) }
                if r == rowCount - 1, r > 0, let p = lastRowPart { regional.append(p) }
                if r == 0, let p = firstRowPart { regional.append(p) }
                // (A header cell spanning rows down takes the header's fill
                // as its own: left to the row's, the band of the row below
                // showed through it — tdf149785's "Key Functions".)
                let tall = (tc["rowSpan"].flatMap(Int.init) ?? 1) > 1
                if let f = regional.compactMap(\.fill).last, r > 0 || firstRowPart == nil || tall { cell.fill = f }
                // A built-in style the deck does not define (the guess: the
                // first accent, white bold header) dresses its first and
                // last column and its last row like the header when the
                // table's flags ask — Medium Style 2's own way (tdf149785's
                // first column was a plain band).
                let emphasised = style == nil && !plain
                    && ((pr?["firstCol"] == "1" && c == 0) || (pr?["lastCol"] == "1" && c == columnCount - 1)
                        || (pr?["lastRow"] == "1" && r == rowCount - 1 && r > 0))
                if emphasised, !(r == 0 && firstRow) || tall { cell.fill = theme.colors["accent1"] ?? Color(0xFF4472C4) }
                // The cell's margins: PowerPoint's 0.1" sides and 0.05" top
                // and bottom unless the cell says otherwise. Its own fill
                // and edge lines (`a:tcPr`) go over the style's.
                let tcPr = tc.first("a:tcPr")
                func margin(_ name: String, _ fallback: Double) -> Double {
                    tcPr?[name].flatMap(Double.init).map { $0 / Pptx.emu } ?? fallback
                }
                cell.padding = EdgeInsets(left: margin("marL", 7.2), top: margin("marT", 3.6),
                                          right: margin("marR", 7.2), bottom: margin("marB", 3.6))
                // A fill the style gave (not this cell's own) stays the style's on a save.
                let ownFill = tcPr?.first("a:solidFill") != nil || tcPr?.first("a:gradFill") != nil || tcPr?.has("a:noFill") == true
                if cell.fill != nil, !ownFill { cell.styleFilled = true }
                if let tcPr {
                    switch tcPr["anchor"] { case "ctr": cell.verticalAlign = "center"; case "b": cell.verticalAlign = "bottom"; default: break }
                    switch tcPr["vert"] {
                    case "vert", "eaVert": cell.textDirection = .down
                    case "vert270": cell.textDirection = .up
                    case "wordArtVert": cell.textDirection = .down; cell.stackedUpright = true
                    default: break
                    }
                    if let f = tcPr.first("a:solidFill") {
                        cell.fill = colors.color(in: f)
                    } else if let g = tcPr.first("a:gradFill") {
                        let stops = g.first("a:gsLst")?.all("a:gs").compactMap { colors.color(in: $0) } ?? []
                        if !stops.isEmpty { cell.fill = stops[stops.count / 2] }
                    } else if tcPr.has("a:noFill") {
                        // The cell says "no fill" over the style's band or
                        // header (tdf164936's empty box).
                        cell.fill = Color(0x00000000)
                    }
                    func line(_ tag: String) -> CellRef.CellLine? {
                        guard let ln = tcPr.first(tag) else { return nil }
                        if ln.has("a:noFill") { return CellRef.CellLine.hidden }
                        let width = ln["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? 1
                        if let f = ln.first("a:solidFill") {
                            // Fully transparent is hidden, not the style's rule.
                            let c = colors.color(in: f)
                            if let c, c.alpha == 0 { return CellRef.CellLine.hidden }
                            // (Dashed as a shape's line is: tableBorderLineStyle's
                            // dots and dashes.)
                            return CellRef.CellLine(width: width, color: c, dash: SlidePainter.dashPattern(PptxReader.dash(ln)))
                        }
                        if let g = ln.first("a:gradFill"), let gs = g.first("a:gsLst")?.all("a:gs").first {
                            return CellRef.CellLine(width: width, color: colors.color(in: gs))
                        }
                        return nil   // a width alone: the style's line, as it is
                    }
                    cell.borders.left = line("a:lnL")
                    cell.borders.right = line("a:lnR")
                    cell.borders.top = line("a:lnT")
                    cell.borders.bottom = line("a:lnB")
                }
                // The style's own rule under its header row and over its last (Medium Style 2's 3 pt
                // white ones: lo-bnc887225, PowerPoint's print): on both cells that share the edge.
                func styled(_ part: TablePartStyle?, _ side: KeyPath<BorderEdges, Bool?>) -> CellRef.CellLine? {
                    guard let part, let e = part.edges, e[keyPath: side] == true, let w = part.borderWidth, w > 1 else { return nil }
                    return CellRef.CellLine(width: w, color: part.borderColor)
                }
                if firstRow {
                    if r == 0, let l = styled(firstRowPart, \.bottom) { if cell.borders.bottom == nil { cell.borders.bottom = l } }
                    if r == 1, let l = styled(firstRowPart, \.bottom) { if cell.borders.top == nil { cell.borders.top = l } }
                }
                if pr?["lastRow"] == "1", rowCount > 1 {
                    if r == rowCount - 1, let l = styled(lastRowPart, \.top) { if cell.borders.top == nil { cell.borders.top = l } }
                    if r == rowCount - 2, let l = styled(lastRowPart, \.top) { if cell.borders.bottom == nil { cell.borders.bottom = l } }
                }
                // The header row's text is light and bold in every styled
                // table PowerPoint offers; a style the deck defines says
                // exactly what (Light Style 2's header is dark text, no fill).
                var look = base
                if let style {
                    // A row band's text look (`band1H`/`band2H` `tcTxStyle`),
                    // under the regional ones, its bands counted as their
                    // fills are, from the row after a header:
                    // table-with-different-font-colors' third row is band2H's
                    // cyan text. (Only the bands' fills were read.)
                    let k = r - (firstRow ? 1 : 0)
                    let rowBandText: [TablePartStyle] = pr?["bandRow"] == "1" && k >= 0
                        ? [_tablePart(style, k % 2 == 0 ? "a:band1H" : "a:band2H")].compactMap { $0 } : []
                    for p in rowBandText + (bandColPart.map { [$0] } ?? []) + regional {
                        if let f = p.font { look.font = f }
                        if let b = p.bold { look.bold = b }
                        if let c = p.textColor { look.color = c }
                    }
                } else if (r == 0 && firstRow && !plain) || emphasised {
                    look.bold = look.bold ?? true
                    look.color = colors.scheme("lt1") ?? Color(0xFFFFFFFF)
                }
                var cellParas: [RichParagraph] = []
                var cellLevels: [Int] = [], cellNumbering: [(type: String, start: Int)?] = []
                for p in tc.first("a:txBody")?.all("a:p") ?? [] {
                    let cellLevel = p.first("a:pPr")?["lvl"].flatMap(Int.init) ?? 0
                    // (The cell's own list style stands between its paragraph and the table's: 65a1be73-class decks name Tahoma and MS PGothic there.)
                    let cellList = LevelStyle.paragraph(tc.first("a:txBody")?.first("a:lstStyle")?.first("a:lvl\(min(cellLevel, 8) + 1)pPr"), colors)
                    var level = LevelStyle.paragraph(p.first("a:pPr"), colors).filled(from: cellList).filled(from: look)
                    cellLevels.append(cellLevel)
                    // A deeper level's text edge and hang, where the
                    // paragraph says neither, are its level's in the
                    // master's other-text style or the presentation's
                    // default: the AES tables' `lvl="1"` and `lvl="2"`
                    // bullets, at half an inch and an inch (marL 457200 and
                    // 914400 in `lvl2pPr` and `lvl3pPr`), stood at the edge.
                    if cellLevel > 0, p.first("a:pPr")?["marL"] == nil, p.first("a:pPr")?["indent"] == nil {
                        let tag = "a:lvl\(min(cellLevel, 8) + 1)pPr"
                        let own = LevelStyle.paragraph(master?.first("p:txStyles")?.first("p:otherStyle")?.first(tag), colors)
                            .filled(from: LevelStyle.paragraph(defaults?.first(tag), colors))
                        level.marL = own.marL
                        level.indent = own.indent
                    }
                    cellNumbering.append(level.bullet == .number ? (level.autoNumType ?? "arabicPeriod", level.autoNumStart ?? 1) : nil)
                    var text = "", runs: [Run] = []
                    var cellKoParens: [Int] = []
                    var cellMath: [String: ImageAttachment] = [:]
                    for child in p.children where child.name == "a:r" || child.name == "a:br" || child.name == "a:fld" || child.name == "a14:m" {
                        // (An equation in a cell is its letters in Cambria Math, as PowerPoint prints them: 3c1f2c4d820b p6's "(𝑎≥6)" was "()" here.)
                        let isMath = child.name == "a14:m"
                        var t = child.name == "a:br" ? "\n" : isMath ? child.descendants("m:t").map { $0.text }.joined() : (child.first("a:t")?.text ?? "")
                        guard !t.isEmpty else { continue }
                        let s = ((isMath ? child.descendants("m:r").first?.first("a:rPr") : child.first("a:rPr")).map { LevelStyle.run($0, colors) } ?? LevelStyle()).filled(from: level)
                        // (An equation in a cell is laid out as an equation, as in a text box, its subscripts and fractions set by `WriterMath`: ja-775ea7b734 p12's
                        // table cells hold e(1,1) with a 13 pt subscript, 3.8 pt down, where the letters alone made "1," and a wrapped "1".)
                        var cellMathId: String? = nil
                        if isMath, let piece = child.children.first(where: { $0.name == "m:oMath" || $0.name == "m:oMathPara" }) {
                            WriterMath.slideScope = true; WriterMath.slideInk = s.color
                            var att = ImageAttachment(data: Data(), width: 1, height: 1, name: piece.name)
                            if let m = WriterMath.register(piece, for: att.id, size: s.size ?? 18) {
                                att.width = m.width; att.height = m.height; att.baseline = m.baseline
                                cellMath[att.id] = att; cellMathId = att.id; t = RichParagraph.inlineImageCharacter
                            }
                            WriterMath.slideScope = false; WriterMath.slideInk = nil
                        }
                        cellKoParens += Self.koParenOffsets(s, t, before: text)
                        text += t
                        // (East Asian letters in the East Asian face, the rest in the Latin one, as a text box's runs: PowerPoint sets
                        // a cell's kana and fullwidth forms in MS PGothic where the Latin slot says Tahoma or Arial.)
                        var segments: [(length: Int, face: String?)] = []
                        if child.name != "a:br" {
                            var segFace: String?? = nil
                            var csFace: String? = nil
                            for ch in t.unicodeScalars {
                                let ea = Self.isEastAsian(ch.value)
                                var face: String? = ea ? _eaFont(s.eaFont ?? s.font, scalar: ch.value, lang: s.lang, latin: s.font) : nil
                                // (A Korean run's ① and the other em-wide symbols are East Asian characters, as in a text box's runs.)
                                if SlideFonts.malgunEmSymbolSet.contains(ch.value), [s.lang, s.altLang].contains(where: { ($0 ?? "").lowercased().hasPrefix("ko") }),
                                   let cjk = OfficeFonts.cjkFallback.first { face = cjk }
                                // (A complex script's letters are set in the run's `a:cs` face, as a text box's are: cc66a30f p18's Persian
                                // table, B Nazanin embedded, was drawn in Calibri's fallback; the spaces and digits after them go with them.)
                                if !ea, let script = Self.complexScript(ch.value), let cf = _csFont(s.csFont, script: script, lang: s.lang, arabicCharset: s.csArabicCharset) { csFace = cf; face = cf }
                                else if !ea, let cf = csFace, !ch.properties.isAlphabetic { face = cf }
                                else if !ea { csFace = nil }
                                if let last = segFace, last == face, !segments.isEmpty { segments[segments.count - 1].length += ch.utf16.count }
                                else { segments.append((ch.utf16.count, face)); segFace = .some(face) }
                            }
                        }
                        if isMath { segments = [(t.utf16.count, "Cambria Math")] }
                        if segments.isEmpty { segments = [(t.utf16.count, nil)] }
                        let firstRun = runs.count
                        for seg in segments {
                            runs.append(Run(length: seg.length, style: CharStyle(
                                bold: s.bold ?? false, italic: s.italic ?? false, underline: s.underline ?? false,
                                fontFamily: seg.face ?? _font(s.font, lang: s.lang, altLang: s.altLang), fontSize: s.size ?? 18,
                                color: s.color ?? colors.scheme("tx1"), letterSpacing: s.spc.flatMap { $0 != 0 ? $0 : nil })))
                        }
                        for k in firstRun ..< runs.count {
                        if let id = cellMathId { runs[k].style.inlineImage = id }
                        // (Kerned from the size `kern` says up, as a text box's runs.)
                        if Self._unkerned(runs[k].style.fontFamily, bold: s.bold ?? false) {
                            runs[k].style.kerningFrom = 0
                        } else { runs[k].style.kerningFrom = s.kern ?? unsaidKern }
                        Self.faceSpacing(&runs[k].style)
                        // (And what a text box's run carries besides: highlight-
                        // test-case's green and yellow in its table's first
                        // cell, drawn plain.)
                        runs[k].style.strikethrough = s.strike ?? false
                        if s.underline == true { runs[k].style.underlineKind = s.underlineKind }
                        if let b = s.baseline { runs[k].style.script = b > 0 ? .superscript : b < 0 ? .subscript : .normal }
                        runs[k].style.highlight = s.highlight
                        runs[k].style.shadow = s.shadow
                        if s.caps == "all" { runs[k].style.caps = true } else if s.caps == "small" { runs[k].style.smallCaps = true }
                        }
                    }
                    var style = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0)
                    if looseKinsoku { style.eastAsian["a:looseKinsoku"] = "1" }
                    if let b = level.latinLnBrk { style.eastAsian["a:latinLnBrk"] = b; style.eastAsian["a:cellLatinLnBrk"] = b }
                    else if p.all("a:r").contains(where: { ($0.first("a:rPr")?["lang"] ?? "").lowercased().hasPrefix("ko") }) { style.eastAsian["a:latinLnBrk"] = "0" }
                    // (A justified cell paragraph is justified, as a text box's: 458870cc p25's cells end every full line at the cell's edge.)
                    switch level.algn { case "ctr": style.alignment = .center; case "r": style.alignment = .right; case "just": style.alignment = .justify; default: break }
                    // Its spacing, as a text box's paragraph has it (aptia's
                    // cells, 6 pt before each paragraph, sat that much high).
                    let endMark: Double? = p.first("a:endParaRPr")?["sz"].flatMap(Double.init).map { $0 / 100 }
                    let size: Double = runs.first?.style.fontSize ?? endMark ?? level.size ?? 18
                    if let m = level.lineMultiple { style.lineSpacing = m } else if let pts = level.linePoints { style.lineHeightPoints = pts.rounded() }
                    // (None before a cell's first paragraph, as none before a
                    // body's: aptia's empty first line and the text under it
                    // both say 6 pt, and the text is 6 lower, not 12.)
                    style.spaceBefore = cellParas.isEmpty ? 0 : level.beforePoints.map { $0.rounded() } ?? (level.beforePercent.map { $0 * size * 1.2 } ?? 0)
                    style.spaceAfter = level.afterPoints.map { $0.rounded() } ?? (level.afterPercent.map { $0 * size * 1.2 } ?? 0)
                    // A bulleted cell paragraph. In a cell the layout puts
                    // the text at `indentLeft` and the bullet in the 18 pt
                    // slot before it (no per-level indent), so the text edge
                    // is the file's, and at least that slot: PowerPoint's
                    // unsaid default is the bullet at 0 with the text right
                    // after it, which this approximates.
                    switch level.bullet {
                    case .char?, .number?:
                        style.list = level.bullet == .char ? .bullet : .numbered
                        style.listLevel = p.first("a:pPr")?["lvl"].flatMap(Int.init) ?? 0
                        style.indentLeft = max(18, level.marL ?? 0)
                        // The file's own text edge and bullet offset when it
                        // says them (the bullet's offset against the 18 pt
                        // slot, as a shape's): the AES tables' "•" at marL 0,
                        // 36 and 72, indent 0, stand at the cell's edge, half
                        // an inch and an inch in, each with its text right
                        // after it, where all three hung 18 pt before the
                        // text.
                        if level.marL != nil || level.indent != nil {
                            style.indentLeft = level.marL ?? 0
                            style.firstLineIndent = (level.indent ?? 0) + 18
                        }
                        // The cell's own bullet, as a shape's: the AES
                        // tables' "•" at every level, where the layout's
                        // own drew "◦" below the first.
                        if level.bullet == .char { style.bulletText = level.bulletGlyph; style.bulletInk = level.bulletInk }
                        style.bulletColor = level.bulletColor
                        style.bulletScale = level.bulletScale
                        // In its own face, as a shape's: AES 2011's Arial
                        // "•" before Verdana text is Arial's 4.9 pt at 14,
                        // where Verdana's 6.9 pushed "that tell" apart.
                        if level.bullet == .char, let f = level.bulletFont,
                           !["wingdings", "symbol", "webdings"].contains(where: { f.lowercased().hasPrefix($0) }) {
                            style.bulletFontFamily = _font(f)
                        }
                        if level.bullet == .char, level.bulletFont?.lowercased() == "wingdings", style.bulletText == "●" {
                            style.bulletStandInFamily = OfficeFonts.calibri
                            style.bulletStandInScale = 0.565 / 0.46
                        }
                        if level.bullet == .char, level.bulletFont?.lowercased().hasPrefix("symbol") == true, style.bulletText == "∗" {
                            style.bulletStandInScale = 0.36 / 0.58
                            style.bulletStandInRaise = 0.28
                        }
                    default:
                        // A plain cell paragraph keeps its own left edge, first-line offset and right margin
                        // (marL, indent, marR): espt 174ab0c2's table labels stand 7.2 pt in and break 13.6 pt short.
                        // (Only a real offset, marL above 0 and no hanging indent: explicit zeros and aptia's centred hanging cell sat worse.)
                        // (A hanging indent holds in a left-aligned cell: 3c1f2c4d820b p4's marL 24.25, indent -24.25 lines break at the 24 pt hang in PowerPoint's print.)
                        let hangs = (level.indent ?? 0) < 0 && (level.marL ?? 0) > 0 && level.algn != "ctr" && level.algn != "r"
                        if (level.marL ?? 0) > 0 || (level.indent ?? 0) > 0, (level.indent ?? 0) >= 0 || hangs {
                            style.indentLeft = level.marL ?? 0
                            style.firstLineIndent = level.indent ?? 0
                        }
                    }
                    // (A cell paragraph that says rtl="1" over Arabic or Hebrew letters, or a list, is right to left as a text box's:
                    // its bullet and hanging indent at the right, algn's page sides swapped for the layout. rtl/7854f160 p13's table:
                    // the "-" bullet stands at the right of the text in PowerPoint's print, 508.4 pt, we drew it at the left end.)
                    if p.first("a:pPr")?["rtl"] == "1",
                       text.unicodeScalars.contains(where: { u in
                           (0x0590 ... 0x08FF ~= u.value || 0xFB1D ... 0xFDFF ~= u.value || 0xFE70 ... 0xFEFF ~= u.value) && u.properties.isAlphabetic })
                        || (p.first("a:pPr")?["rtl"] == "1" && style.list != nil) {
                        style.rightToLeft = true
                        // (The layout adds the list's own 18 pt slot to the start edge; the file's marL and indent are the whole of it:
                        // marL 27, indent -27 puts the text 27 pt in and the bullet at the edge, as PowerPoint prints it.)
                        if style.list != nil { style.bulletAtEnd = true; if level.marL != nil || level.indent != nil { style.indentLeft -= 18 } }
                        if style.alignment == .left { style.alignment = .right } else if style.alignment == .right { style.alignment = .left }
                    }
                    if let marR = level.marR, marR > 0 { style.indentRight = marR }
                    // An empty paragraph is as tall as its end mark says
                    // (`endParaRPr`): a row grows for 96 pt of nothing
                    // (tdf144092), as it would for a letter that size.
                    let end = p.first("a:endParaRPr").map { LevelStyle.run($0, colors) }
                    var para = text.isEmpty
                        ? RichParagraph(text: "", runs: [Run(length: 0, style: CharStyle(bold: end?.bold ?? look.bold ?? false,
                                                                                          fontFamily: _font(end?.font ?? look.font),
                                                                                          fontSize: end?.size ?? look.size ?? 18, color: look.color))], style: style)
                        : RichParagraph(text: text, runs: runs, style: style)
                    para.inlineImages = cellMath
                    para.cell = cell
                    // (Lab tblrow2, PowerPoint's print: a cell paragraph with fontAlgn="ctr" has no first-line loss at a percent spacing,
                    // its row is the full m x 1.2 x size (MS PGothic 28 pt 150% 50.40, Arial 24 43.20); without fontAlgn the loss stays.)
                    if !text.isEmpty, style.lineSpacing > 1.0, p.first("a:pPr")?["fontAlgn"] == "ctr" { para.style.cellFullFirstLine = true }
                    if !text.isEmpty, style.lineSpacing > 1.0 {
                        // (The face's share of the line below the baseline, Windows metrics; a face we hold none for is taken as Arial.)
                        let big = runs.max { ($0.style.fontSize ?? 0) < ($1.style.fontSize ?? 0) }
                        func share(_ f: String?) -> Double { f.flatMap { SlideFonts.windowsDescentShare($0) } ?? SlideFonts.arialDescentShare }
                        para.style.cellDescentShare = max(share(big?.style.fontFamily), share(end?.font.map { _font($0) }))
                    }
                    if !cellKoParens.isEmpty { para.style.eastAsian["a:hangParens"] = cellKoParens.map(String.init).joined(separator: ",") }
                    // (A closing mark, ) ] and the like, in a zh run of a cell hangs past the margin as it does in a text box: 1892a5a76df6 p70's
                    // "（複數決標屬採購策略）" stays on one line in a 149 pt cell, PowerPoint's print; lab zhhang.)
                    if p.all("a:r").contains(where: { r in
                        (r.first("a:rPr")?["lang"] ?? "").lowercased().hasPrefix("zh")
                            && (r.first("a:t")?.text ?? "").unicodeScalars.contains(where: { [0xFF09, 0x300D, 0x300F, 0x3011, 0x3015, 0x300B, 0x3009, 0xFF1A, 0xFF1B, 0xFF01, 0xFF1F].contains($0.value) }) }) {
                        para.style.eastAsian["a:hangClosingZh"] = "1"
                    }
                    if !text.isEmpty, let algn = p.first("a:pPr")?["fontAlgn"], algn == "t" || algn == "ctr" || algn == "b",
                       let face = runs.max(by: { ($0.style.fontSize ?? 0) < ($1.style.fontSize ?? 0) })?.style.fontFamily,
                       let m = SlideFonts.windowsAscentDescent(face) {
                        // (The default stands the baseline 1.2 x (1 - share) down; these stand the glyph box in the 1.2 line.)
                        let target: Double
                        switch algn { case "t": target = m.ascent; case "ctr": target = (1.2 - (m.ascent + m.descent)) / 2 + m.ascent; default: target = 1.2 - m.descent }
                        para.style.cellFontAlignDrop = target - 1.2 * (1 - m.descent / (m.ascent + m.descent))
                        // (With fontAlgn ctr the first line keeps the whole of its extra (cellFullFirstLine), where other rows trim it by
                        // (m-1) x 0.3 + k em, k = 0.3 - 1.2 x the face's share below the baseline: the baseline stands that much lower, within 0.1 pt
                        // of lab tblrow2 and 99f6ddd1 p12's 150% print for Arial 24 (0.221 em), MS PGothic 36 (0.217) and Meiryo UI 24 (0.258).)
                        if para.style.cellFullFirstLine {
                            let k = max(0, 0.3 - 1.2 * (para.style.cellDescentShare ?? 0.1897))
                            para.style.cellFontAlignDrop! += (style.lineSpacing - 1) * 0.3 + k
                        }
                    }
                    cellParas.append(para)
                }
                if cellParas.isEmpty {
                    var para = RichParagraph(text: "", style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0))
                    para.cell = cell
                    cellParas = [para]
                } else if cellNumbering.contains(where: { $0 != nil }), cellLevels.count == cellParas.count {
                    // A cell numbers its own paragraphs, from its own
                    // `startAt`: customGeo's crosswalk counts 1 to 6 down
                    // six cells, each starting where the last left off.
                    var own = RichDocument(paragraphs: cellParas)
                    Self._numberRuns(&own, levels: cellLevels, numbering: cellNumbering, prefix: "pptx-\(tableId)-\(r)-\(column)")
                    cellParas = own.paragraphs
                    for (k, v) in own.listFormats { cellListFormats[k] = v }
                    for (k, v) in own.listRestarts { cellListRestarts[k] = v }
                }
                paragraphs += cellParas
            }
            // A row short of the grid's columns (a span with no merged
            // cells after it) is filled out with empty cells, in the
            // table's own lines: LIBRE_OFFICE-100610's survey row ends in
            // two such, ruled black in PowerPoint's print.
            // (Their lines over a neighbour's own: the survey's two are
            // closed at the top, under the title cell's white edge.)
            let gridded = plain && (styleId.isEmpty || styleId.hasPrefix("{5940675A"))
            while !widths.isEmpty, column < widths.count {
                var para = RichParagraph(text: "", style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0))
                var cell = CellRef(table: tableId, row: r, column: column, span: 1, rowSpan: 1)
                if gridded {
                    let edge = CellRef.CellLine(width: 1, color: colors.scheme("tx1") ?? Color(0xFF000000))
                    cell.borders.left = edge; cell.borders.right = edge; cell.borders.top = edge; cell.borders.bottom = edge
                }
                para.cell = cell
                paragraphs.append(para)
                column += 1
            }
        }
        guard !paragraphs.isEmpty else { return nil }
        var doc = RichDocument(paragraphs: paragraphs)
        for (k, v) in cellListFormats { doc.listFormats[k] = v }
        for (k, v) in cellListRestarts { doc.listRestarts[k] = v }
        if !widths.isEmpty { doc.tableColumns[tableId] = widths }
        // The rows' own heights (`a:tr h`), as minimums: PowerPoint keeps a
        // row that tall however little is in it.
        let rowHeights = tbl.all("a:tr").map { ($0["h"].flatMap(Double.init) ?? 0) / Pptx.emu }
        let accent = theme.colors["accent1"] ?? Color(0xFF4472C4)
        var tableGradient: SlideFill? = nil
        var tableShadow: CharShadow? = nil
        var ts = plain
            ? TableStyle(borders: styleId.isEmpty || styleId.hasPrefix("{5940675A"), headerRow: firstRow, borderColor: colors.scheme("tx1"))
            : TableStyle(borders: true, headerRow: firstRow, headerFill: accent,
                         bandFill: banded ? DeckController.tint(accent, 0.40) : nil,
                         bandAltFill: banded ? DeckController.tint(accent, 0.20) : nil,
                         borderColor: Color(0xFFFFFFFF))
        if !styleId.isEmpty { ts.styleId = styleId }
        ts.totalRow = pr?["lastRow"] == "1"
        ts.firstColumn = pr?["firstCol"] == "1"
        ts.lastColumn = pr?["lastCol"] == "1"
        ts.bandedColumns = pr?["bandCol"] == "1"
        if plain { ts.bandRows = banded }
        // A table with no style (or "Table Grid") is ruled in 1 pt black,
        // as PowerPoint draws tdf135843_export's grid, not the editor's ½.
        if plain, ts.borders { ts.borderWidth = 1 }
        if let style {
            // As the deck's style has it: the header's own fill (none is
            // none, not a tint), band 1 and band 2 over the whole table's
            // fill — which is the table background (`a:tblBg`, a themed
            // style's gradient, by its middle colour) when the cells say
            // none — and the whole table's rules.
            let b1 = _tablePart(style, "a:band1H"), b2 = _tablePart(style, "a:band2H")
            // The style's own effect (a themed style's `effectRef`: the theme's soft shadow) falls from the table.
            if let ref = style.first("a:tblBg")?.first("a:effectRef"), let idx = ref["idx"].flatMap(Int.init), idx > 0,
               theme.effectStyles.indices.contains(idx - 1) {
                var c = colors
                c.placeholder = colors.color(in: ref)
                tableShadow = LevelStyle.outerShadow(theme.effectStyles[idx - 1].first("a:effectLst"), c)
            }
            var under = whole?.fill
            if under == nil || under == Color(0x00000000), let bg = style.first("a:tblBg") {
                if let ref = bg.first("a:fillRef"), ref["idx"] != "0" {
                    if let idx = ref["idx"].flatMap(Int.init), theme.fillStyles.indices.contains(idx - 1),
                       theme.fillStyles[idx - 1].name == "a:gradFill" {
                        var c = colors
                        c.placeholder = colors.color(in: ref)
                        c.tableGradient = true
                        c.pageBackground = true  // a table's gradient mixes its tints in linear light (Word's print, tstyles2)
                        // The theme's gradient runs over the whole table,
                        // under its cells, and a band's tint lies on it as
                        // it is: bnc480256's "Themed Style" tables shade
                        // from top to bottom across their rows. (Where the
                        // gradient does not read, its middle colour under
                        // every cell, as before.)
                        if let gradient = PptxReader.gradient(theme.fillStyles[idx - 1], colors: c), gradient.stops.count >= 2 {
                            tableGradient = gradient
                            under = nil
                        } else {
                            let stops = theme.fillStyles[idx - 1].first("a:gsLst")?.all("a:gs").compactMap { c.color(in: $0) } ?? []
                            under = stops.isEmpty ? c.placeholder : stops[stops.count / 2]
                        }
                    } else {
                        under = colors.color(in: ref)
                    }
                } else if let f = bg.first("a:fill") {
                    under = f.first("a:solidFill").flatMap(colors.color(in:))
                }
            }
            // (No fill under the cells is nothing to lay a tint over: a
            // style whose cells say `a:noFill` and that has no table
            // background had its 20% band mixed with black.)
            if let u = under, u.a < 0.002 { under = nil }
            func over(_ fill: Color?) -> Color? {
                // A translucent band over the table's own fill.
                guard let fill, let under, (fill.value >> 24) & 0xFF < 0xFF else { return fill ?? under }
                return DeckController.blend(fill, over: under)
            }
            ts.headerFill = firstRow ? (over(firstRowPart?.fill) ?? Color(0x00000000)) : nil
            ts.bandFill = banded ? over(b1?.fill) : under
            ts.bandAltFill = banded ? over(b2?.fill) : under
            if let b = whole?.borders { ts.borders = b }
            if let c = whole?.borderColor { ts.borderColor = c }
            if let e = whole?.edges { ts.edges = e }
            if let w = whole?.borderWidth { ts.borderWidth = w }
        }
        for (r, h) in rowHeights.enumerated() where h > 0 { ts.rowHeights[r] = h }
        // A row holding rowSpan continuation cells, set shorter than 2.0 pt plus the top margin of the cells
        // that start in it, still occupies that much (labs tbl-rows12/13/14: 2.75 pt with marT 0.75, 5.60 pt
        // with marT 3.6; insets of the continuation cells, face, size and empty paragraph do not move it).
        for (r, tr) in tbl.all("a:tr").enumerated() {
            let cells = tr.all("a:tc")
            guard cells.contains(where: { _xmlOn($0["vMerge"]) }) else { continue }
            let starts = cells.filter { !_xmlOn($0["vMerge"]) && !_xmlOn($0["hMerge"]) }
            guard !starts.isEmpty else { continue }
            let marT = starts.map { ($0.first("a:tcPr")?["marT"].flatMap(Double.init) ?? 45720) / Pptx.emu }.max() ?? 0
            if rowHeights[r] < 2 + marT { ts.rowHeights[r] = 2 + marT }
        }
        doc.tableStyles[tableId] = ts
        // PowerPoint sets a table as wide as its grid, whatever width the graphic frame states (a Google Slides export states 3000000
        // EMU on every table; e2a1fcdb p8's two columns, 268 + 692 pt, were squeezed into 236 pt here and wrapped a character a line).
        if transform == nil, !widths.isEmpty, frame.width > 0 {
            frame = Rect.fromLTWH(frame.left, frame.top, widths.reduce(0, +), frame.height)
        }
        var st = ShapeState(id: id(), name: el.descendant("p:cNvPr")?["name"] ?? "Table", kind: .table, frame: frame,
                            rotation: 0, fill: nil, outline: nil, outlineWidth: 0, anchor: .top,
                            insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil, text: doc,
                            font: _font(base.font), size: base.size ?? 18, color: base.color ?? colors.scheme("tx1") ?? Color(0xFF000000),
                            listIndent: 18)
        st.fillStyle = tableGradient
        st.shadow = tableShadow
        if el.first("p:nvGraphicFramePr")?.first("p:cNvGraphicFramePr")?.first("a:graphicFrameLocks")?["noChangeAspect"] == "1" { st.aspectLock = true }
        // The table's own fill (a fill in `a:tblPr`), behind every cell:
        // tdf127237's cells all say no fill, and stand on the table's blue.
        if let pr = tbl.first("a:tblPr") {
            if let solid = pr.first("a:solidFill"), let c = colors.color(in: solid) {
                st.fill = c
            } else if let g = pr.first("a:gradFill"), let gradient = PptxReader.gradient(g, colors: colors), gradient.stops.count >= 2 {
                st.fillStyle = gradient
            }
        }
        st.sourceXML = PptxXML.serialize(el)
        st.sourceText = doc
        st.sourcePart = part
        st.readShape = ReadShape(st)
        return st
    }

}
