// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

extension SlideContext {
    /// A chart this app draws, from its part's cached values; kept as read
    /// too, and written back through that part while it is unchanged.
    func _chart(_ el: XNode, _ transform: ((Rect) -> Rect)?, id: () -> Int) -> ShapeState? {
        guard let ref = (el.descendant("c:chart") ?? el.descendant("cx:chart"))?["r:id"],
              let rel = package.rels(part).first(where: { $0.id == ref && !$0.external }),
              let space = package.xml(rel.target).map(ChartXML.canonical) else { return nil }
        // A chart pasted from another file brings that file's colours with
        // it: a theme override part, whose scheme stands in for the deck's
        // wherever the chart says `schemeClr` (tdf149985's greens, where
        // the deck's own accents are Office's blue and orange).
        var colors = colors
        // (So does one on a slide whose master has another theme: aascu
        // 5864's charts under the Office theme, drawn in Concourse's.)
        var overridden = foreignTheme
        // (And its own fonts: aascu 5864's employment chart, under a
        // master in Lucida Sans Unicode, is Calibri by its override.)
        var overrideFont: String?
        if let over = package.rels(rel.target).first(where: { $0.kind == "themeOverride" && !$0.external }),
           let face = package.xml(over.target)?.descendant("a:minorFont")?.first("a:latin")?["typeface"], !face.isEmpty {
            overrideFont = face
        }
        if let over = package.rels(rel.target).first(where: { $0.kind == "themeOverride" && !$0.external }),
           let scheme = package.xml(over.target)?.descendant("a:clrScheme") {
            overridden = true
            for child in scheme.children {
                let name = String(child.name.drop { $0 != ":" }.dropFirst())
                if let c = child.first("a:srgbClr")?["val"].flatMap(PptxTheme.hex)
                    ?? child.first("a:sysClr")?["lastClr"].flatMap(PptxTheme.hex) {
                    colors.theme.colors[name] = c
                }
            }
        }
        // The chart's own colour map, over the slide's: chart_pt_color_bg1's
        // slide swaps bg1 for dark, its chart keeps bg1 light, and its
        // `bg1 lumMod 85%` slice is light grey in PowerPoint's print.
        if let map = space.first("c:clrMapOvr") { for (k, v) in map.attrs { colors.map[k] = v } }
        // (An Excel 2016 chart, `cx:chartSpace` — waterfall, funnel, histogram, box and whisker, sunburst, treemap — comes
        // through the choice of an mc:AlternateContent; the fallback picture is what an older reader draws.)
        let chartex = space.name == "cx:chartSpace"
        guard var chart = chartex ? ChartXML.readChartex(space, color: { colors.color(in: $0) }) : ChartXML.read(space, color: { colors.color(in: $0) }),
              var frame = el.first("p:xfrm").flatMap(_xfrmRect) else { return nil }
        if chartex {
            chart.waterfallLegendTotal = true
            // (A pareto's cumulative line has no legend entry in PowerPoint's print, only the columns' series: chartex-lab pareto-gapwidth.)
            if chart.pareto { chart.hiddenLegendEntries.insert(chart.series.count) }
            // (PowerPoint joins a waterfall's columns unless the file turns the lines off: lo-forum-mso-de-138303's.)
            if chart.waterfallTotals != nil, space.descendant("cx:layoutPr")?.first("cx:visibility")?["connectorLines"] != "0" { chart.waterfallConnectors = true }
            let style = package.rels(rel.target).first(where: { $0.kind == "chartStyle" && !$0.external }).flatMap { package.xml($0.target) }
            ChartXML.applyCxTextSizes(&chart, space: space, style: style)
        }
        // A chart that names no face is in its own slide's theme font — a
        // deck of several masters (aascu 5864's census charts, Calibri;
        // cooper's, Verdana) was drawn in the first master's.
        // (Its Japanese face too: d776ec3f p23's override says MS PGothic where the deck's theme says Yu Gothic, and the print's 12 pt labels are PGothic.)
        if let over = package.rels(rel.target).first(where: { $0.kind == "themeOverride" && !$0.external }),
           let minor = package.xml(over.target)?.descendant("a:minorFont"), (minor.first("a:ea")?["typeface"] ?? "").isEmpty,
           let j = minor.all("a:font").first(where: { $0["script"] == "Jpan" })?["typeface"], !j.isEmpty {
            chart.japaneseFaceOverride = j
        }
        if chart.font == nil, let face = overrideFont ?? (foreignTheme ? theme.minor : nil) {
            chart.font = face
            if chart.titleFont == nil { chart.titleFont = chart.font }
        }
        if overridden {
            // A series that names a theme slot, or leaves its colour to the
            // cycle, is drawn against the deck's theme — which is not this
            // chart's. Each gets the colour it has in the chart's own.
            let accents = (1 ... 6).compactMap { colors.scheme("accent\($0)") }
            if chart.type.isPie, accents.count == 6 {
                for i in chart.categories.indices where chart.pointColors[i] == nil { chart.pointColors[i] = chart.pointColor(i, accents: accents) }
            }
            for i in chart.series.indices where chart.series[i].color == nil {
                if let slot = chart.series[i].scheme { chart.series[i].color = colors.scheme(slot) }
                else if accents.count == 6 { chart.series[i].color = chart.color(series: i, accents: accents) }
                if chart.series[i].color != nil { chart.series[i].scheme = nil }
            }
        }
        if space.first("c:spPr") == nil, chart.textColor == nil, let sv = space.first("c:style")?["val"].flatMap(Int.init), (33 ... 40).contains(sv) {
            chart.textColor = Color(0xFF000000)
        }
        if let t = transform { frame = t(frame) }
        var st = ShapeState(id: id(), name: el.descendant("p:cNvPr")?["name"] ?? "Chart", kind: .chart(chart), frame: frame,
                            rotation: 0, fill: nil, outline: nil, outlineWidth: 0, anchor: .top,
                            insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil, text: nil,
                            font: nil, size: 18, color: Color(0xFF000000), listIndent: 18)
        st.sourceXML = PptxXML.serialize(el)
        st.sourcePart = part
        st.sourceChart = chart
        // The chart area's own picture or gradient fill (chart-picture-bg),
        // drawn under the plot.
        if let pr = space.first("c:spPr") ?? space.first("cx:spPr") {
            if let b = pr.first("a:blipFill"), let blip = b.first("a:blip"), let rid = blip["r:embed"],
               let img = package.rels(rel.target).first(where: { $0.id == rid }), !img.external,
               package.parts[img.target] != nil {
                var f = SlideFill(image: images.attachment(img.target, package, blip: blip))
                (f.imageAlpha, f.duotone) = PptxReader.blipEffects(blip, colors: colors)
                f.imageLevels = PptxReader.blipLevels(blip)
                f.imageInset = PptxReader.stretchInset(b)
                // Tiled as a shape's picture fill is (chart-texture-bg's
                // paper at its own size, where it was one sheet stretched).
                if b.first("a:tile") != nil {
                    PptxReader.tile(b.first("a:tile"), image: package.parts[img.target], into: &f)
                }
                st.fillStyle = f
            } else if let f = pr.first("a:solidFill"), let c = colors.color(in: f) {
                st.fillStyle = SlideFill(color: c)
            } else if let g = pr.first("a:gradFill"), let f = PptxReader.gradient(g, colors: colors), f.stops.count >= 2 {
                // (0338b5a8's dark circle-path gradient behind its pies.)
                st.fillStyle = f
            }
            // The chart area's outline.
            if let ln = pr.first("a:ln"), !ln.has("a:noFill"), let f = ln.first("a:solidFill"), let c = colors.color(in: f) {
                st.outline = c
                st.outlineWidth = ln["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? 0.75
            } else if chartex, let ln = pr.first("a:ln"), let g = ln.first("a:gradFill"), let f = PptxReader.gradient(g, colors: colors),
                      f.stops.count >= 2 {
                // (A chartex chart area's gradient edge, red to blue across the frame: chartex-lab2 waterfall.)
                st.outline = f.stops[0].color
                st.outlineFill = f
                st.outlineWidth = ln["w"].flatMap(Double.init).map { $0 / Pptx.emu } ?? 0.75
            }
        }
        // (Where the file gives the area no fill, its Office 2007 style does: 33-40 white, 41-48 black.)
        if st.fillStyle == nil, space.first("c:spPr") == nil, let a = chart.areaFill, !chart.areaNoFill { st.fillStyle = SlideFill(color: a) }
        // (Styles 33-40: a plain white area and dark text, where the file sets neither: 1c1295c3 p18. The text is dk1, not the slide's tx1.)
        if st.fillStyle == nil, space.first("c:spPr") == nil, let sv = space.first("c:style")?["val"].flatMap(Int.init), (33 ... 40).contains(sv) {
            st.fillStyle = SlideFill(color: Color(0xFFFFFFFF))
        }
        // The chart's own drawing (`c:userShapes`): shapes placed in the
        // chart's frame by fractions of it, or by an offset and size —
        // tdf149985's grey oval over its last bar. Drawn over the chart,
        // never written (the chart part keeps them).
        if let us = package.rel(rel.target, kind: "chartUserShapes"), let drawing = package.xml(us.target) {
            func renamed(_ n: XNode) -> XNode {
                let name = n.name.hasPrefix("cdr:") ? "p:" + n.name.dropFirst(4) : n.name
                let c = XNode(name: name, attrs: n.attrs)
                c.text = n.text
                c.children = n.children.map(renamed)
                return c
            }
            func at(_ n: XNode?) -> Offset? {
                guard let x = n?.first("cdr:x").flatMap({ Double($0.text) }), let y = n?.first("cdr:y").flatMap({ Double($0.text) }) else { return nil }
                return Offset(x, y)
            }
            for anchor in drawing.children {
                let target: Rect
                if anchor.name == "cdr:relSizeAnchor", let a = at(anchor.first("cdr:from")), let b = at(anchor.first("cdr:to")) {
                    target = Rect.fromLTRB(frame.left + a.dx * frame.width, frame.top + a.dy * frame.height,
                                           frame.left + b.dx * frame.width, frame.top + b.dy * frame.height)
                } else if anchor.name == "cdr:absSizeAnchor", let a = at(anchor.first("cdr:from")),
                          let cx = anchor.first("cdr:ext")?["cx"].flatMap(Double.init), let cy = anchor.first("cdr:ext")?["cy"].flatMap(Double.init) {
                    target = Rect.fromLTWH(frame.left + a.dx * frame.width, frame.top + a.dy * frame.height, cx / Pptx.emu, cy / Pptx.emu)
                } else { continue }
                guard let child = anchor.children.first(where: { ["cdr:sp", "cdr:grpSp", "cdr:cxnSp"].contains($0.name) }) else { continue }
                let shape = renamed(child)
                // Its own box (the group's, or the shape's), laid onto the anchor's.
                let own = (shape.first("p:spPr") ?? shape.first("p:grpSpPr"))?.first("a:xfrm").flatMap(_xfrmRect)
                let map: (Rect) -> Rect = { r in
                    guard let own, own.width > 0, own.height > 0 else { return target }
                    let sx = target.width / own.width, sy = target.height / own.height
                    return Rect.fromLTWH(target.left + (r.left - own.left) * sx, target.top + (r.top - own.top) * sy, r.width * sx, r.height * sy)
                }
                let tree = XNode(name: "p:spTree", attrs: [:])
                tree.children = [shape]
                shapes(in: tree, transform: map, into: &st.chartDrawing, id: id)
            }
        }
        return st
    }

    /// A SmartArt's drawing part (`dsp:drawing`, reached from the data
    /// part's `dsp:dataModelExt relId`) as shapes at `frame`: its elements
    /// are DrawingML shapes under another prefix, so they read as `p:` ones.
    static let customTextId = -125551
    func _diagram(_ el: XNode, frame: Rect, id: () -> Int) -> [ShapeState] {
        guard let relIds = el.descendant("dgm:relIds"), let dm = relIds["r:dm"],
              let dataPart = package.rels(part).first(where: { $0.id == dm })?.target,
              let data = package.xml(dataPart) else { return [] }
        func renamed(_ n: XNode) -> XNode {
            let name = n.name.hasPrefix("dsp:") ? "p:" + n.name.dropFirst(4) : n.name
            let c = XNode(name: name, attrs: n.attrs)
            c.text = n.text
            c.children = n.children.map(renamed)
            return c
        }
        func related(_ key: String) -> (String, XNode)? {
            guard let rid = relIds[key], let p = package.rels(part).first(where: { $0.id == rid })?.target,
                  let x = package.xml(p) else { return nil }
            return (p, x)
        }
        var tree: XNode? = nil
        var drawingPart = part
        if let relId = data.descendant("dsp:dataModelExt")?["relId"],
           let dp = package.rels(part).first(where: { $0.id == relId })?.target,
           let drawing = package.xml(dp), let t = drawing.first("dsp:spTree"),
           t.children.contains(where: { $0.name == "dsp:sp" || $0.name == "dsp:grpSp" }) {
            // PowerPoint's own drawing of the diagram. (LibreOffice writes
            // the part with nothing in it; that counts as none.)
            tree = renamed(t)
            // (The drawing's `lnSpc` below 100% is kept: the print sets a SmartArt line at the percent of its face's line, as a plain box does; 7c3069f9808a's 14.1 pt wrapped pitch is 0.9 x 1.306 em, PMingLiU's diagram line (`SlideFonts.diagramEastAsianLine`). 32 Latin SmartArt decks score worse with it ignored.)
            drawingPart = dp
            // The drawing's `fontRef` is the quick style's, whatever the
            // colour scheme says: a white node of an outlined scheme
            // (accent3_1) still carries `lt1` there, and PowerPoint, which
            // lays the diagram out afresh, shows its text in the scheme's
            // own text colour (`txFillClrLst` of the node's style label) —
            // dark. Across the corpus the two disagree only where that list
            // names a colour, and an empty list leaves the fontRef to rule;
            // so a named one replaces it (tdf93830's text was white on white).
            if let scheme = related("r:cs")?.1 {
                var labels: [String: String] = [:]
                for pt in data.first("dgm:ptLst")?.all("dgm:pt") ?? [] {
                    if let id = pt["modelId"], let l = pt.first("dgm:prSet")?["presStyleLbl"] { labels[id] = l }
                }
                var textColors: [String: XNode] = [:]
                for l in scheme.all("dgm:styleLbl") {
                    if let name = l["name"], let c = l.first("dgm:txFillClrLst")?.children.first { textColors[name] = c }
                }
                // A node drawn as a shape with a text companion (pyramid1's
                // `levelTx`, label `revTx`): the layout shows the text in the
                // companion, so its colour rules where the node's list is
                // empty (pyramid's grey tiers carry `lt1` in the drawing,
                // PowerPoint prints `tx1`).
                var shows: [String: String] = [:], companion: Set<String> = []
                for cxn in data.first("dgm:cxnLst")?.all("dgm:cxn") ?? [] where cxn["type"] == "presOf" {
                    guard let src = cxn["srcId"], let dst = cxn["destId"] else { continue }
                    shows[dst] = src
                    if labels[dst] == "revTx" { companion.insert(src) }
                }
                for sp in tree?.all("p:sp") ?? [] {
                    guard let id = sp["modelId"], let label = labels[id],
                          let color = textColors[label] ?? shows[id].flatMap({ companion.contains($0) ? textColors["revTx"] : nil }),
                          let font = sp.first("p:style")?.first("a:fontRef") else { continue }
                    font.children = [color]
                }
            }
            // PowerPoint lays the diagram out afresh from the data, so a
            // paragraph's spacing the data states stands over the cached
            // drawing's (5c820695 p12: the data's 12 pt before the two paragraphs
            // above "普及者" moves the centred text 12.5 pt down in the print,
            // the stale drawing has none). Only where the paragraphs pair up.
            do {
                var texts: [String: XNode] = [:], shownBy: [String: String] = [:]
                for pt in data.first("dgm:ptLst")?.all("dgm:pt") ?? [] { if let id = pt["modelId"], let t = pt.first("dgm:t") { texts[id] = t } }
                for cxn in data.first("dgm:cxnLst")?.all("dgm:cxn") ?? [] where cxn["type"] == "presOf" {
                    if let src = cxn["srcId"], let dst = cxn["destId"] { shownBy[dst] = src }
                }
                for sp in tree?.all("p:sp") ?? [] {
                    guard let id = sp["modelId"], let src = shownBy[id], let dt = texts[src], let tx = sp.first("p:txBody") else { continue }
                    let dparas = dt.all("a:p"), tparas = tx.all("a:p")
                    guard dparas.count == tparas.count else { continue }
                    for (dp, tp) in zip(dparas, tparas) {
                        guard let dpr = dp.first("a:pPr"), let tpr = tp.first("a:pPr") else { continue }
                        for name in ["a:spcBef", "a:spcAft"] {
                            guard let d = dpr.first(name) else { continue }
                            if let i = tpr.children.firstIndex(where: { $0.name == name }) { tpr.children[i] = d } else { tpr.children.insert(d, at: 0) }
                        }
                    }
                }
            }
            // A point whose text size the author set (`custT`): its shape is
            // marked here (the drawing's ids are all 0) and keeps that size
            // below, overflowing or not.
            var custom: Set<String> = [], owner: [String: String] = [:]
            for pt in data.first("dgm:ptLst")?.all("dgm:pt") ?? [] {
                guard let id = pt["modelId"], let pr = pt.first("dgm:prSet") else { continue }
                if pr["custT"] == "1" { custom.insert(id) }
                if let o = pr["presAssocID"] { owner[id] = o }
            }
            // (And a shape that shows such a point's text by a `presOf`
            // connection, whoever it belongs to: tdf145528's centre tile,
            // the document's, shows the 72 pt "☺" and keeps it.)
            for cxn in data.first("dgm:cxnLst")?.all("dgm:cxn") ?? [] where cxn["type"] == "presOf" {
                if let src = cxn["srcId"], let dst = cxn["destId"], custom.contains(src) { custom.insert(dst) }
            }
            for sp in tree?.all("p:sp") ?? [] {
                guard let id = sp["modelId"], custom.contains(id) || owner[id].map(custom.contains) == true else { continue }
                sp.descendant("p:cNvPr")?.attrs["id"] = String(Self.customTextId)
            }
        } else if let (_, layoutDef) = related("r:lo") {
            // No drawing (a deck LibreOffice saved): laid out here from the
            // data and the layout definition.
            tree = DiagramLayout.render(data: data, layout: layoutDef, colors: related("r:cs")?.1, style: related("r:qs")?.1,
                                        frame: Rect.fromLTWH(0, 0, frame.width, frame.height))
            // Its pictures are the data's (`r:embed` in a point's fill
            // names the data part's relationship): picture-strip's
            // numbered tabs were looked for among the slide's, and drawn
            // as nothing.
            drawingPart = dataPart
        }
        guard let tree else { return [] }
        // The diagram's own background and outline (`dgm:bg`, `dgm:whole`
        // in the data): a rectangle the size of the frame, behind everything
        // — smartart-background's green between its boxes.
        let fillNames: Set<String> = ["a:solidFill", "a:gradFill", "a:blipFill", "a:pattFill"]
        let bgFill = data.first("dgm:bg")?.children.first { fillNames.contains($0.name) }
        let wholeLine = data.first("dgm:whole")?.first("a:ln")
        if bgFill != nil || wholeLine != nil {
            let sp = XNode(name: "p:sp", attrs: [:])
            let nv = XNode(name: "p:nvSpPr", attrs: [:])
            nv.children = [XNode(name: "p:cNvPr", attrs: ["id": "0", "name": "diagram background"]),
                           XNode(name: "p:cNvSpPr", attrs: [:]), XNode(name: "p:nvPr", attrs: [:])]
            let spPr = XNode(name: "p:spPr", attrs: [:])
            let xfrm = XNode(name: "a:xfrm", attrs: [:])
            xfrm.children = [XNode(name: "a:off", attrs: ["x": "0", "y": "0"]),
                             XNode(name: "a:ext", attrs: ["cx": String(Int(frame.width * Pptx.emu)),
                                                          "cy": String(Int(frame.height * Pptx.emu))])]
            let geom = XNode(name: "a:prstGeom", attrs: ["prst": "rect"])
            geom.children = [XNode(name: "a:avLst", attrs: [:])]
            let line = wholeLine ?? XNode(name: "a:ln", attrs: [:])
            if wholeLine == nil { line.children = [XNode(name: "a:noFill", attrs: [:])] }
            spPr.children = [xfrm, geom, bgFill ?? XNode(name: "a:noFill", attrs: [:]), line]
            sp.children = [nv, spPr]
            tree.children.insert(sp, at: 0)
        }
        var ctx = SlideContext(package: package, part: drawingPart, slide: slide, layout: layout, master: master,
                               colors: colors, theme: theme, defaults: defaults, slideSize: slideSize, images: images,
                               unsaidKern: unsaidKern, looseKinsoku: looseKinsoku)
        ctx.inDiagram = true
        var out: [ShapeState] = []
        ctx.shapes(in: tree, transform: { r in r.shift(Offset(frame.left, frame.top)) }, into: &out, id: id)
        out = out.flatMap { s -> [ShapeState] in
            guard let box = s.uprightBox, s.text != nil else { return [s] }
            var shape = s
            shape.text = nil
            shape.uprightBox = nil
            var text = s
            text.id = id()
            text.kind = .textBox
            text.frame = box
            text.rotation = 0
            text.flipH = false
            text.flipV = false
            text.fill = nil
            text.fillStyle = nil
            text.outline = nil
            text.customPath = nil
            text.shadow = nil
            text.glowRadius = nil
            text.softEdge = nil
            text.scene3d = nil
            text.shapeInsets = .zero
            text.insets = s.uprightInsets
            text.uprightBox = nil
            return [shape, text]
        }
        // A preset this app has no outline for is drawn as a box, which
        // serves for the rounded and snipped rectangles diagrams favour but
        // not for a gear (gear6, gear9): those are left out.
        // The drawing part caches one layout of the text; PowerPoint fits it
        // to the shapes afresh, so every text shrinks to fit here too —
        // but for one at a size its author set, which PowerPoint leaves
        // alone (tdf125551's 32 pt labels run out of their bars).
        for i in out.indices where out[i].text != nil && out[i].fileId != Self.customTextId && !out[i].keepsSize { out[i].autofit = true }
        for i in out.indices where out[i].text != nil { out[i].naturalLines = true }
        return out.filter { s in
            if case .geometry(let p) = s.kind {
                // Round things and curved arrows look nothing like their box.
                let name = p.rawValue
                if SlidePainter.drawablePresets.contains(name) || s.customPath != nil { return true }
                for part in ["gear", "Arrow", "arc", "Arc", "pie", "chord", "donut", "moon", "sun", "cloud", "heart",
                             "lightning", "Circle", "ellipse"] where name.containsSubstring(part) { return false }
                return true
            }
            // A freeform whose guides this app cannot evaluate would be a
            // labelled box here: nothing is better.
            if case .opaque(let o) = s.kind, o.freeform == nil { return false }
            return true
        }
    }

    /// One region of a table style (`a:wholeTbl`, `a:firstRow`, `a:band1H`…):
    /// its cells' fill and rules, and its text's colour and weight.
    struct TablePartStyle {
        var fill: Color? = nil
        var textColor: Color? = nil
        var bold: Bool? = nil
        var borders: Bool? = nil
        var borderColor: Color? = nil
        /// Which of its six rules it draws, and their width (points),
        /// where its `a:tcBdr` names each side.
        var edges: BorderEdges? = nil
        var borderWidth: Double? = nil
        /// `a:tcTxStyle`'s face: a theme slot (`fontRef idx`) or a name.
        var font: String? = nil
    }

    func _tablePart(_ style: XNode, _ name: String) -> TablePartStyle? { Self.tablePart(style, name, colors: colors) }

    /// A region of a table style read with the given colours (the editor's gallery reads a built-in style's too).
    static func tablePart(_ style: XNode, _ name: String, colors: ColorContext) -> TablePartStyle? {
        guard let part = style.first(name) else { return nil }
        var r = TablePartStyle()
        if let tc = part.first("a:tcStyle") {
            if let f = tc.first("a:fill") {
                if let s = f.first("a:solidFill") {
                    r.fill = colors.color(in: s)
                } else if let g = f.first("a:gradFill") {
                    // Its middle colour stands for the gradient.
                    let stops = g.first("a:gsLst")?.all("a:gs").compactMap { colors.color(in: $0) } ?? []
                    if !stops.isEmpty { r.fill = stops[stops.count / 2] }
                } else if f.has("a:noFill") {
                    r.fill = Color(0x00000000)
                }
            } else if let ref = tc.first("a:fillRef"), ref["idx"] != "0" {
                r.fill = colors.color(in: ref)
            }
            if let bdr = tc.first("a:tcBdr"), !bdr.children.isEmpty {
                var visible = false
                var shown: [String: Bool] = [:]
                for side in ["a:insideH", "a:insideV", "a:left", "a:right", "a:top", "a:bottom"] {
                    if let ref = bdr.first(side)?.first("a:lnRef") {
                        // The theme's line style in the referred colour.
                        if ref["idx"] == "0" { shown[side] = false; continue }
                        visible = true
                        shown[side] = true
                        if r.borderColor == nil { r.borderColor = colors.color(in: ref) }
                        continue
                    }
                    guard let ln = bdr.first(side)?.first("a:ln") else { continue }
                    if ln.has("a:noFill") { shown[side] = false; continue }
                    visible = true
                    shown[side] = true
                    if r.borderColor == nil, let f = ln.first("a:solidFill") { r.borderColor = colors.color(in: f) }
                    if r.borderWidth == nil, let w = ln["w"].flatMap(Double.init) { r.borderWidth = w / Pptx.emu }
                }
                r.borders = visible
                // Each side as it says (a side it leaves out has no rule:
                // tdf135843_insideH's rows ruled, its columns not).
                if visible {
                    r.edges = BorderEdges(top: shown["a:top"] ?? false, left: shown["a:left"] ?? false,
                                          bottom: shown["a:bottom"] ?? false, right: shown["a:right"] ?? false,
                                          insideH: shown["a:insideH"] ?? false, insideV: shown["a:insideV"] ?? false)
                }
            }
        }
        if let tx = part.first("a:tcTxStyle") {
            r.textColor = colors.color(in: tx)
            switch tx["b"] { case "on": r.bold = true; case "off": r.bold = false; default: break }
            if let idx = tx.first("a:fontRef")?["idx"] { r.font = idx == "major" ? "+mj-lt" : "+mn-lt" }
            if let name = tx.first("a:font")?.first("a:latin")?["typeface"] { r.font = name }
        }
        return r
    }

    /// A shape's or picture's outer shadow: its own effects', or — saying
    /// none — its style's theme effect (`effectRef`, the referred colour
    /// as `phClr`), as Office 2007's themes give every shape one.
    /// A shape's inner shadow, its own or its style's.
    /// A shape's top bevel: its own `a:sp3d`, else its theme effect
    /// style's (`effectRef`) — the Office 2007 theme's intense effect, a
    /// 5 × 2 pt bevel under a three-point light. Nil for none, or one of
    /// no width.
    func _shapeBevel(_ spPr: XNode?, _ style: XNode?) -> ShapeBevel? {
        func read(_ sp3d: XNode?, _ scene: XNode?) -> ShapeBevel? {
            guard let bev = sp3d?.first("a:bevelT") else { return nil }
            let w = (bev["w"].flatMap(Double.init) ?? 76200) / Pptx.emu, h = (bev["h"].flatMap(Double.init) ?? 76200) / Pptx.emu
            guard w > 0.1, h > 0 else { return nil }
            var b = ShapeBevel(width: w, height: h)
            if let rig = scene?.first("a:lightRig")?["rig"] { b.rig = rig }
            b.preset = bev["prst"] ?? "circle"
            if let rig = scene?.first("a:lightRig") {
                let turns: [String: Double] = ["t": 0, "tr": 45, "r": 90, "br": 135, "b": 180, "bl": 225, "l": 270, "tl": 315]
                b.turn = turns[rig["dir"] ?? "t"] ?? 0
                if let r = rig.first("a:rot") {
                    func deg(_ a: String) -> Double { (r[a].flatMap(Double.init) ?? 0) / 60000 }
                    b.rot = [deg("lat"), deg("lon"), deg("rev")]
                    b.turn = 0
                }
            }
            if let m = sp3d?["prstMaterial"] { b.material = m }
            b.diagram = sp3d?["starlingDiagram"] != nil
            return b
        }
        if let spPr, spPr.first("a:sp3d") != nil || spPr.first("a:scene3d") != nil {
            return read(spPr.first("a:sp3d"), spPr.first("a:scene3d"))
        }
        guard let ref = style?.first("a:effectRef"), let idx = ref["idx"].flatMap(Int.init), idx > 0,
              theme.effectStyles.indices.contains(idx - 1) else { return nil }
        let effect = theme.effectStyles[idx - 1]
        return read(effect.first("a:sp3d"), effect.first("a:scene3d"))
    }

    func _shapeInnerShadow(_ spPr: XNode?, _ style: XNode?) -> CharShadow? {
        func read(_ effects: XNode?, _ c: ColorContext) -> CharShadow? {
            guard let sh = effects?.first("a:innerShdw"), let color = c.color(in: sh) else { return nil }
            let dist = (sh["dist"].flatMap(Double.init) ?? 0) / Pptx.emu
            let dir = (sh["dir"].flatMap(Double.init) ?? 0) / 60000 * .pi / 180
            return CharShadow(color: color, dx: dist * cos(dir), dy: dist * sin(dir),
                              blur: (sh["blurRad"].flatMap(Double.init) ?? 0) / Pptx.emu)
        }
        if let own = spPr?.first("a:effectLst") { return read(own, colors) }
        if spPr?.first("a:effectDag") != nil { return nil }
        guard let ref = style?.first("a:effectRef"), let idx = ref["idx"].flatMap(Int.init), idx > 0,
              theme.effectStyles.indices.contains(idx - 1) else { return nil }
        var c = colors
        c.placeholder = colors.color(in: ref)
        return read(theme.effectStyles[idx - 1].first("a:effectLst"), c)
    }

    func _shapeShadow(_ spPr: XNode?, _ style: XNode?) -> CharShadow? {
        if let own = spPr?.first("a:effectLst") { return LevelStyle.outerShadow(own, colors) }
        if spPr?.first("a:effectDag") != nil { return nil }
        guard let ref = style?.first("a:effectRef"), let idx = ref["idx"].flatMap(Int.init), idx > 0,
              theme.effectStyles.indices.contains(idx - 1) else { return nil }
        var c = colors
        c.placeholder = colors.color(in: ref)
        return LevelStyle.outerShadow(theme.effectStyles[idx - 1].first("a:effectLst"), c)
    }

    func _frameLabel(_ el: XNode) -> String {
        let uri = el.descendant("a:graphicData")?["uri"] ?? ""
        if uri.hasSuffix("/chart") || uri.containsSubstring("chartex") { return "Chart" }
        if uri.hasSuffix("/diagram") { return "SmartArt" }
        if uri.hasSuffix("/table") { return "Table" }
        if uri.containsSubstring("ole") { return "Embedded object" }
        return "Object"
    }

    func _opaque(_ el: XNode, label: String, _ transform: ((Rect) -> Rect)?, id: () -> Int, framed: Bool = true) -> ShapeState? {
        let x = el.first("p:xfrm") ?? el.first("p:spPr")?.first("a:xfrm") ?? el.first("p:grpSpPr")?.first("a:xfrm")
            ?? el.descendant("a:xfrm") ?? el.descendant("p:xfrm")
        guard var frame = x.flatMap(_xfrmRect) ?? (framed ? nil : Rect.fromLTWH(0, 0, 0, 0)) else { return nil }
        if x != nil, let t = transform { frame = t(frame) }
        let name = el.descendant("p:cNvPr")?["name"] ?? label
        return ShapeState(id: id(), name: name,
                          kind: .opaque(OpaqueObject(xml: PptxXML.serialize(el), label: label, sourcePart: part)),
                          frame: frame, rotation: 0, fill: nil, outline: nil, outlineWidth: 0, anchor: .top,
                          insets: EdgeInsets(left: 0, top: 0, right: 0, bottom: 0), prompt: nil, text: nil,
                          font: nil, size: 18, color: Color(0xFF000000), listIndent: 18)
    }

    // MARK: Text

    struct TextBody {
        var document: RichDocument
        var anchor: TextAnchor
        var insets: EdgeInsets
        var font: String
        var size: Double
        var color: Color
        var listIndent: Double
        /// `normAutofit`: shrink the text to fit, by `fontScale` now.
        var autofit = false
        var fontScale = 1.0
        var lineReduction = 0.0
        /// The insets are fractions of the font size (a diagram's margins)
        /// and shrink with it.
        var insetsFollowFont = false
        /// A diagram laid out here: the shapes that end at one size.
        var sizeGroup: String? = nil
        /// A diagram's text box that grows to its text: the text keeps its size.
        var keepsSize = false
        /// `bodyPr compatLnSpc="0"`: the lines stand on Word's line (1.3 of the face's win height), as a diagram's do.
        var wordLines = false
        var generatedHang = false
        /// `bodyPr wrap="none"`.
        var noWrap = false
        /// `bodyPr anchorCtr="1"`.
        var anchorCentred = false
        /// The file's own `bodyPr vert` and `wrap` and its autofit element (`a:normAutofit`, `a:spAutoFit`, `a:noAutofit`), so a save states them again.
        var bodyVert: String? = nil
        var bodyWrap: String? = nil
        var fitRule: String? = nil
        /// `bodyPr spcFirstLastPara="1"`: the first paragraph keeps its space before.
        var keepsFirstSpace = false
        /// `bodyPr vert`: 1 a quarter clockwise, -1 anticlockwise.
        var textTurn = 0
        var textStacked = 0
        var uprightIdeographs = false
        var sidewaysDigits = false
        /// The text's camera turned about its axis (`scene3d/camera/rot
        /// rev`), degrees clockwise.
        var textSpin = 0.0
        var textRev = 0.0
        var textScene: Scene3D? = nil
        /// `bodyPr numCol` and `spcCol` (points).
        var columns = 1
        var columnGap = 0.0
        var warp: TextWarp? = nil
        var runLooks: [[RunLook]] = []
    }

    /// The master text style a placeholder (or plain shape) draws from.
    /// A master that has no title or body style (one written by another
    /// program: subtitle-animation-save's has no `p:txStyles` at all)
    /// leaves PowerPoint's own: a title at 44 pt in the heading face, a
    /// body at 28 with a "•", both at 90% line spacing.
    func _masterStyle(_ ph: XNode?) -> XNode? {
        let styles = master?.first("p:txStyles")
        guard let ph else { return nil }
        switch ph["type"] ?? "obj" {
        case "title", "ctrTitle": return styles?.first("p:titleStyle") ?? Self.builtInTitleStyle
        // (A content placeholder, `p:ph` with no type, does not take the
        // built-in bullet: outliner-list-style's unbulleted first level.)
        case "body", "subTitle": return styles?.first("p:bodyStyle") ?? Self.builtInBodyStyle
        case "obj": return styles?.first("p:bodyStyle") ?? Self.builtInContentStyle
        // (Text typed into a picture placeholder is body text: 28 pt in
        // pic-placeholder-with-text's print, where the other style's 18
        // stood. Its kin — table, chart, clip art, diagram, media — read so
        // too.)
        case "pic", "tbl", "chart", "clipArt", "dgm", "media": return styles?.first("p:bodyStyle") ?? Self.builtInContentStyle
        default: return styles?.first("p:otherStyle")
        }
    }

    static let builtInTitleStyle = MiniXML.parse(Array("""
        <p:titleStyle><a:lvl1pPr><a:lnSpc><a:spcPct val="90000"/></a:lnSpc><a:spcBef><a:spcPct val="0"/></a:spcBef>\
        <a:buNone/><a:defRPr sz="4400"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mj-lt"/>\
        <a:ea typeface="+mj-ea"/><a:cs typeface="+mj-cs"/></a:defRPr></a:lvl1pPr></p:titleStyle>
        """.utf8))
    static let builtInContentStyle = MiniXML.parse(Array("""
        <p:bodyStyle><a:lvl1pPr><a:lnSpc><a:spcPct val="90000"/></a:lnSpc>\
        <a:defRPr sz="2800"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill>\
        <a:latin typeface="+mn-lt"/><a:ea typeface="+mn-ea"/><a:cs typeface="+mn-cs"/></a:defRPr></a:lvl1pPr></p:bodyStyle>
        """.utf8))
    static let builtInBodyStyle = MiniXML.parse(Array("""
        <p:bodyStyle><a:lvl1pPr><a:lnSpc><a:spcPct val="90000"/></a:lnSpc><a:spcBef><a:spcPts val="1000"/></a:spcBef>\
        <a:buFont typeface="Arial"/><a:buChar char="&#8226;"/><a:defRPr sz="2800"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill>\
        <a:latin typeface="+mn-lt"/><a:ea typeface="+mn-ea"/><a:cs typeface="+mn-cs"/></a:defRPr></a:lvl1pPr></p:bodyStyle>
        """.utf8))

    /// Level `n` (0-based) as the whole chain resolves it, lowest layer first.
    func _level(_ n: Int, shapeList: XNode?, ph: XNode?, inherited: (layout: XNode?, master: XNode?)) -> LevelStyle {
        let tag = "a:lvl\(n + 1)pPr"
        var layers: [XNode?] = [
            shapeList?.first(tag),
            inherited.layout?.first("p:txBody")?.first("a:lstStyle")?.first(tag),
            inherited.master?.first("p:txBody")?.first("a:lstStyle")?.first(tag),
            _masterStyle(ph)?.first(tag),
            defaults?.first(tag),
        ]
        // A text box or drawn shape on a slide takes the presentation's
        // default text style, not the master's `otherStyle` — PowerPoint
        // centres a box whose deck says algn="ctr" there while the master
        // says "l" (45541_Header's title slide). otherStyle only fills in
        // what the default leaves unsaid.
        if ph == nil {
            layers = [shapeList?.first(tag), defaults?.first(tag),
                      master?.first("p:txStyles")?.first("p:otherStyle")?.first(tag)]
        } else if ["title", "ctrTitle", "body", "subTitle", "obj"].contains(ph?["type"] ?? "obj") {
            // And the reverse: a title or body draws from the master's title
            // and body styles alone. The presentation's default is for the
            // other objects — alterman_security's says i="1" at every level,
            // and PowerPoint shows its bodies upright.
            layers.removeLast()
        }
        // (Each layer's picture bullet from its own part.)
        let layoutPart = package.rel(part, kind: "slideLayout")?.target
        let masterPart = layoutPart.flatMap { package.rel($0, kind: "slideMaster")?.target }
        func pictures(_ owner: String?) -> (String) -> ImageAttachment? {
            { rid in
                guard let owner, let rel = self.package.rels(owner).first(where: { $0.id == rid }), !rel.external,
                      self.package.parts[rel.target] != nil else { return nil }
                return self.images.attachment(rel.target, self.package)
            }
        }
        let owners: [String?] = ph == nil ? [part, nil, masterPart] : [part, layoutPart, masterPart, masterPart, nil]
        var s = LevelStyle()
        for (k, layer) in layers.enumerated() {
            var one = LevelStyle.paragraph(layer, colors, picture: pictures(k < owners.count ? owners[k] : nil))
            // (A text box's size is the deck's default or 18 pt, never the master's `otherStyle` one: 65a1be73's second
            // master says 12 pt there and PowerPoint prints its slide-number text boxes at 18.)
            if ph == nil, k == 2 { one.size = nil }
            // (A date, footer or slide-number placeholder the master has no placeholder for takes the deck's default size, not
            // `otherStyle`'s: ko-ca2dc787 p35-37's number is 14 pt bold in PowerPoint's print, 18 in ours.)
            if let t = ph?["type"], ["dt", "ftr", "sldNum"].contains(t), inherited.master == nil, k == 3 { one.size = nil }
            s = s.filled(from: one)
        }
        // (A text box's tab distance is the deck's default text style's, an inch where that says none: the master's `otherStyle`
        // 36 pt is not read for it. ko-439a1778 p16's boxes put their tabbed lines at 72 pt steps in PowerPoint's print.)
        if ph == nil, defaults != nil, defaults?.first(tag)?["defTabSz"] == nil, shapeList?.first(tag)?["defTabSz"] == nil { s.defTab = nil }
        return s
    }

    /// The face East Asian letters are set in: the run's `a:ea`, a theme
    /// reference's East Asian face, else the theme's face for the script
    /// the letter is of (the run's language picks Han's) — nil where
    /// nothing names one (the Latin face serves, as before).
    func _eaFont(_ f: String?, scalar: UInt32, lang: String?, latin: String? = nil) -> String? {
        let major = f == "+mj-ea" || f == "+mj-lt" || f == "+mj-cs"
        let table = major ? theme.majorScript : theme.minorScript
        // A Latin-only face named for the East Asian slot of a run that is not marked Japanese (Google Slides exports
        // name Calibri there, lang en-US) has no letters for kana and kanji: PowerPoint sets them in MS Gothic
        // (054ae4d7 p8 pitch 101.6 pt). Runs marked ja keep the named face (6effb0bd, 5cf98ad4: Arial, lang ja-JP).
        if let f, !f.hasPrefix("+") {
            if Self.latinOnlyOfficeFaces.contains(f), scalar >= 0x3040, scalar <= 0x9FFF, !(lang ?? "").lowercased().hasPrefix("ja") { return "MS Gothic" }
            return f
        }
        if let named = table["ea"], !named.isEmpty { return named }
        // (An East Asian slot that names nothing, the theme's too, is set in the run's Latin face where that is an East Asian face:
        // ja 505a93a9 p14's runs name MS UI Gothic as Latin only, and PowerPoint sets their kanji and （） in it, brackets half an em.)
        if let latin, Self.eastAsianOfficeFaces.contains(latin) { return latin }
        let l = (lang ?? "").lowercased()
        // (PowerPoint's print, bug64693, a theme whose East Asian slot is empty: Chinese letters of a run that names
        // that slot (+mn-ea) are SimSun, of a run that names none are Microsoft YaHei, not the theme's Hans face.)
        if l == "zh-cn", scalar >= 0x3400, scalar <= 0x9FFF || (scalar >= 0xF900 && scalar <= 0xFAFF) {
            if let f, f.hasSuffix("-ea") { return "SimSun" }
            if f == nil { return "Microsoft YaHei" }
        }
        let script: String
        switch scalar {
        case 0x3040 ... 0x30FF, 0x31F0 ... 0x31FF, 0xFF66 ... 0xFF9F: script = "Jpan"
        case 0xAC00 ... 0xD7AF, 0x1100 ... 0x11FF, 0x3130 ... 0x318F: script = "Hang"
        default:
            // (A mark of a run that names no language and whose Latin face is a Korean one is set in that face, not in the theme's Hans
            // face: ko-d8f0a8af p90's "【상표 유형】" in 함초롬바탕, a theme with an empty East Asian slot and Hans 宋体, is Malgun Gothic's
            // 0.518 em in PowerPoint's print.)
            if l.isEmpty, let latin, latin.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }) { return latin }
            script = l.hasPrefix("ja") ? "Jpan" : l.hasPrefix("ko") ? "Hang" : (l == "zh-tw" || l == "zh-hk" || l == "zh-mo") ? "Hant" : l.hasPrefix("zh") ? "Hans" : "Hans"
        }
        // (A theme with an empty East Asian slot and no Hang entry: PowerPoint sets Hangul in Malgun Gothic, the Korean UI face
        // (ko-dcc7e p38's layout header, bold 16 pt, Hangul 16.0 pt advance in the print, ours 14.72 in the stand-in).)
        if script == "Hang", table[script] == nil { return "Malgun Gothic" }
        return table[script]
    }

    static let eastAsianOfficeFaces: Set<String> = ["MS UI Gothic", "MS PGothic", "MS Gothic", "MS Mincho", "MS PMincho", "ＭＳ Ｐゴシック", "ＭＳ ゴシック", "ＭＳ 明朝", "ＭＳ Ｐ明朝",
        "Malgun Gothic", "Gulim", "Dotum", "Batang", "Gungsuh", "SimSun", "SimHei", "NSimSun", "Microsoft YaHei", "Microsoft JhengHei", "PMingLiU", "MingLiU", "DFKai-SB"]

    static let latinOnlyOfficeFaces: Set<String> = ["Calibri", "Arial", "Times New Roman", "Cambria", "Verdana", "Tahoma", "Georgia", "Trebuchet MS"]

    /// Offsets (in the paragraph's UTF-16) of a ")" after a Latin letter in a run whose language or alternate language is Korean:
    /// PowerPoint hangs it past the margin like one after Hangul (ko-4f5289a9 p6 "(전류원 DB, CB Counter)" keeps its ")" 0.8 pt past the cell).
    static func koParenOffsets(_ s: LevelStyle, _ t: String, before text: String) -> [Int] {
        guard [s.lang, s.altLang].contains(where: { ($0 ?? "").lowercased().hasPrefix("ko") }) else { return [] }
        var out: [Int] = [], at = text.utf16.count, prev: UInt16 = text.utf16.last ?? 0
        for u in t.utf16 { if u == 0x29, (prev >= 0x41 && prev <= 0x5A) || (prev >= 0x61 && prev <= 0x7A) { out.append(at) }; prev = u; at += 1 }
        return out
    }

    static func isEastAsian(_ v: UInt32) -> Bool {
        switch v {
        case 0x1100 ... 0x11FF, 0x2E80 ... 0x303F, 0x3040 ... 0x30FF, 0x3130 ... 0x318F, 0x31F0 ... 0x31FF,
             0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF, 0xAC00 ... 0xD7AF, 0xF900 ... 0xFAFF, 0xFF01 ... 0xFF60, 0xFF66 ... 0xFF9F, 0xFFE0 ... 0xFFE6: return true
        default: return false
        }
    }

    /// The face a complex script's letters are set in: the run's `a:cs`,
    /// a theme reference's complex-script face, else the theme's face for
    /// that script — nil where nothing names one (the Latin face serves).
    func _csFont(_ f: String?, script: String, lang: String? = nil, arabicCharset: Bool = false) -> String? {
        // (The theme's Arabic face is the one for runs tagged with an Arabic-script language. An untagged run, which takes the
        // deck's en-US, draws its Arabic letters in Arial whatever the theme names: rtl/e08da366's titles, theme major "Majalla UI",
        // ArialMT 44 pt in PowerPoint's print, while the ar-SA runs of f355b7fc and eb7ab2c5 draw "Majalla UI" as Sakkal Majalla.)
        if f == nil || f!.hasPrefix("+"), script == "Arab" {
            let l = (lang ?? "").lowercased()
            if !["ar", "fa", "ur", "ps", "sd", "ug", "ku"].contains(where: { l.hasPrefix($0) }) { return "Arial" }
        }
        switch f {
        case nil, "+mn-cs", "+mn-lt", "+mn-ea": return theme.minorScript["cs"] ?? theme.minorScript[script]
        case "+mj-cs", "+mj-lt", "+mj-ea": return theme.majorScript["cs"] ?? theme.majorScript[script]
        default:
            // (A complex-script face the machine lacks, declared with the Arabic charset, not the deck's own: PowerPoint draws its Arabic letters in Arial. d04ef266's
            // "B Lotus", "B Zar" and "B Mitra" are ArialMT in the print; ours were DejaVu Sans, 4% narrower, so a line took a word more.)
            if script == "Arab", arabicCharset, let f, !f.isEmpty, !SlideFonts.isEmbedded(f), !OfficeFonts.isWindowsComplexFace(f),
               OfficeFonts.installed(f) == nil { return "Arial" }
            return f
        }
    }

    /// A run's spacing for a face drawn by a stand-in of other widths,
    /// in a text box and in a table cell alike.
    static func faceSpacing(_ cs: inout CharStyle) {
        // Arial Black, which no face shipped here has: drawn in the
        // stand-in's bold, at Arial Black's own widths (`SlideFonts.face`)
        // — the plain face left "TRADE SHOW" on one line where PowerPoint
        // breaks it in two. (Segoe UI, Tahoma, Franklin Gothic and the
        // rest have their own widths there too.)
        // (Archivo Black is heavy as it stands: asked for bold it was
        // thickened again by a stroke, which a translucent fill shows as a
        // darker ring: ThemeColorTransparency.)
        if let f = cs.fontFamily?.lowercased(), f == "arial black" || f == "franklin gothic heavy" {
            cs.bold = !SlideFonts.hasHeavyStandIn
        }
        // (Aptos is no longer tightened by a spacing: it is set at its own measured widths and kern pairs, `SlideFonts.face`.)
        // Calibri Light, set in Calibri's regular: 0.0054 em a letter
        // tighter — PowerPoint's lines in it are 1.2 to 1.6% shorter than
        // ours, the same in all twenty decks (69 lines compared). (Its own
        // widths, `SlideFontWidths.calibriLight`, came out worse: a face
        // set at its own widths is not kerned here, and its titles are.)
        if cs.fontFamily?.lowercased() == "calibri light" {
            cs.letterSpacing = (cs.letterSpacing ?? 0) - 0.0054 * (cs.fontSize ?? 18)
            // (Its bold run, set at the regular's widths (`SlideFonts.face`), is a further 0.006 em a letter tighter in
            // PowerPoint's print: 6d178027's 48 pt lines, 40 words measured, run 2.4% under Calibri's regular less the above.)
            // (A bold run is set at Light's own bold table (`SlideFonts.face`), not Carlito's regular: the regular's spacing is not wanted.)
            if cs.bold { cs.letterSpacing = (cs.letterSpacing ?? 0) + 0.0054 * (cs.fontSize ?? 18) }
        }
        // Consolas, set in Liberation Mono: 0.55 em a letter, not
        // 0.6 (lines 8.7% wide).
        if cs.fontFamily?.lowercased() == "consolas" {
            cs.letterSpacing = (cs.letterSpacing ?? 0) - 0.05 * (cs.fontSize ?? 18)
        }
    }

}
