// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Charts in Writer: a .docx keeps a chart (`c:chart` in a drawing) as an
// object of its size, which the layout cannot draw. Its part is read as
// Slides reads a chart (`ChartXML.read`) against the document's theme,
// and drawn by Slides' painter through `RichLayout.objectPainter`, by the
// attachment's id. Without this, 61745's page — two charts and nothing
// else — printed blank.

import Flutter
import FlutterSwiftBridge
import Foundation

/// The registries' lock: one thread in the browser, and no NSLock in its
/// Foundation (see `OfficeFonts.declaredLock`).
#if os(WASI)
struct RegistryLock { func lock() {}; func unlock() {} }
#else
typealias RegistryLock = NSLock
#endif

enum WriterCharts {
    private struct Entry {
        let chart: Chart
        let theme: DeckTheme
        /// The chart area's own fill and border (`c:chartSpace/c:spPr`):
        /// Word's default is white with a light grey line.
        let fill: Color?
        let line: Color?
        let lineWidth: Double
    }

    private nonisolated(unsafe) static var entries: [String: Entry] = [:]
    private static let lock = RegistryLock()

    /// Reads the chart in `space` (a chart part's `c:chartSpace`), its
    /// colours from `themePart` (the document's `a:theme`), for the
    /// object attachment `id`; false where it is no chart this can draw.
    @discardableResult
    static func register(_ space: XNode, for id: String, themePart: Data?, themeOverride: Data? = nil) -> Bool {
        let space = ChartXML.canonical(space)
        let pptxTheme = PptxTheme(themePart.flatMap { XNode.parse($0) })
        let colors = ColorContext(theme: pptxTheme)
        let chartex = space.name == "cx:chartSpace"
        guard var chart = chartex ? ChartXML.readWordChartex(space) : ChartXML.read(space, color: { colors.color(in: $0) })
        else { return false }
        // (Word for Windows sets a theme's East Asian text in Mincho and
        // JhengHei where the theme names no East Asian face: zh-2a241df1's
        // and zh-61aaad09's tables, whose `a:ea` is "".)
        if RichTextTheme.wordWindowsPages,
           let ea = themePart.flatMap({ XNode.parse($0) })?.descendant("a:minorFont")?.first("a:ea"), (ea["typeface"] ?? "").isEmpty {
            chart.windowsMinchoText = true
            chart.windowsMinchoTitle = !(space.descendant("c:title").map(ChartXML._traditional) ?? false)
        }
        // (Word for Mac sets it in the theme's Hans and Hant faces — the
        // chart's own theme override's where it has one, zh-b8de3ae2's
        // pies' 等线: `Chart.macSimplifiedFace`.)
        if OfficeFonts.wordForMacFaces,
           let minor = (themeOverride ?? themePart).flatMap({ XNode.parse($0) })?.descendant("a:minorFont"),
           (minor.first("a:ea")?["typeface"] ?? "").isEmpty {
            func script(_ name: String) -> String? {
                minor.all("a:font").first(where: { $0["script"] == name })?["typeface"].flatMap { $0.isEmpty ? nil : $0 }
            }
            chart.macSimplifiedFace = OfficeFonts.wordMacIdeographFace(script("Hans") ?? "宋体") ?? "SimSun"
            chart.macTraditionalFace = script("Hant").flatMap(OfficeFonts.wordMacIdeographFace)
            chart.titleTraditional = space.descendant("c:title").map(ChartXML._traditional) ?? false
        }
        // (An axis title in its own size: zh-b8de3ae2's "千元", `sz="1000"`,
        // is 10.08pt in Word for Mac's print, where ours took the 13.3 of
        // PowerPoint's default and stood 15pt wider at the plot's left.)
        if chart.axisTitleSize == nil, !chartex,
           let plot = space.first("c:chart")?.first("c:plotArea"),
           let t = plot.children.first(where: { ["c:valAx", "c:catAx", "c:dateAx"].contains($0.name) && $0.first("c:title") != nil })?.first("c:title"),
           let sz = (t.descendant("a:rPr")?["sz"] ?? t.descendant("a:defRPr")?["sz"]).flatMap(Double.init), sz > 0 {
            chart.axisTitleSize = sz / 100
        }
        var theme = DeckTheme()
        theme.headingFont = pptxTheme.major
        theme.bodyFont = pptxTheme.minor
        if let text = colors.scheme("tx1") { theme.text = text }
        if let background = colors.scheme("bg1") { theme.background = background }
        let accents = (1 ... 6).compactMap { colors.scheme("accent\($0)") }
        if accents.count == 6 { theme.accents = accents }
        let area = space.first(chartex ? "cx:spPr" : "c:spPr")
        let fill = area?.first("a:solidFill").flatMap { colors.color(in: $0) }
        let ln = area?.first("a:ln")
        // (A chartex part that says nothing is framed as Word frames it,
        // in D9D9D9: chartex's box-and-whisker chart.)
        let line = ln?.first("a:solidFill").flatMap { colors.color(in: $0) }
            ?? (chartex && area == nil ? Color(0xFFD9D9D9) : nil)
        let entry = Entry(chart: chart, theme: theme, fill: fill, line: line,
                          lineWidth: (ln?["w"]).flatMap { Double($0) }.map { $0 / 12700 } ?? 0.75)
        lock.lock()
        entries[id] = entry
        lock.unlock()
        installHooks()
        return true
    }

    /// Whether a chart is registered for `attachment`.
    static func has(_ attachment: ImageAttachment) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[attachment.id] != nil
    }

    /// Draws the chart registered for `attachment` into `rect`; false
    /// where none is.
    static func paint(_ attachment: ImageAttachment, _ canvas: any Canvas, _ rect: Rect, _ pxPerPt: Double) -> Bool {
        lock.lock()
        let entry = entries[attachment.id]
        lock.unlock()
        guard let entry else { return false }
        if let fill = entry.fill {
            let p = Paint()
            p.style = .fill
            p.color = fill
            canvas.drawRect(rect, p)
        }
        ChartPainter.paint(entry.chart, canvas, rect, pxPerPt: pxPerPt, theme: entry.theme)
        if let line = entry.line {
            let p = Paint()
            p.style = .stroke
            p.strokeWidth = max(1, entry.lineWidth * pxPerPt)
            p.color = line
            canvas.drawRect(rect, p)
        }
        return true
    }

    /// The layout's hooks for the objects Writer draws itself: charts,
    /// and the metafile pictures of embedded objects (`WriterMetafiles`).
    static func installHooks() {
        if RichLayout.drawsObject == nil {
            RichLayout.drawsObject = { WriterCharts.has($0) || WriterMetafiles.has($0) || WriterGroups.has($0) || WriterMath.has($0) }
        }
        if RichLayout.objectPainter == nil {
            RichLayout.objectPainter = { attachment, canvas, rect, pxPerPt in
                WriterCharts.paint(attachment, canvas, rect, pxPerPt) || WriterMetafiles.paint(attachment, canvas, rect)
                    || WriterGroups.paint(attachment, canvas, rect, pxPerPt) || WriterMath.paint(attachment, canvas, rect, pxPerPt)
            }
        }
        if RichLayout.objectFitter == nil {
            RichLayout.objectFitter = { attachment, width in WriterMath.fit(attachment, width: width) }
        }
    }
}

/// Metafile pictures in Writer: an embedded object (`w:object`, an OLE
/// package or document) shows the WMF or EMF its `v:imagedata` names —
/// the icon and its caption, or the first page of the document. No image
/// codec reads those, so the object printed as nothing (tika-3388's
/// "約翰的測試文件 .msg", WordWithAttachments' five attachments). Played
/// by Slides' player, by the attachment's id, with the bitmaps it
/// carries — an attachment's icon (WordWithAttachments' package and Word
/// document, tika-3388's .msg) — decoded beside it as the layout decodes
/// its pictures: until then they are left out, and an export waits.
enum WriterMetafiles {
    private nonisolated(unsafe) static var entries: [String: Metafile] = [:]
    private nonisolated(unsafe) static var decoded: [String: Image] = [:]
    private nonisolated(unsafe) static var decoding: Set<String> = []
    private static let lock = RegistryLock()

    /// Whether a metafile's bitmap is still being decoded.
    static var hasPendingImages: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !decoding.isEmpty
    }

    /// A metafile's bitmap, decoded once; nil while it decodes.
    private static func image(_ bitmap: ImageAttachment) -> Image? {
        lock.lock()
        defer { lock.unlock() }
        if let image = decoded[bitmap.id] { return image }
        guard !decoding.contains(bitmap.id), !bitmap.data.isEmpty else { return nil }
        decoding.insert(bitmap.id)
        let bytes = [UInt8](bitmap.data), id = bitmap.id
        Task { @MainActor in
            var image: Image? = nil
            if let codec = try? await instantiateImageCodec(bytes) {
                image = (try? await codec.getNextFrame())?.image
                codec.dispose()
            }
            lock.lock()
            decoding.remove(id)
            if let image { decoded[id] = image }
            lock.unlock()
        }
        return nil
    }

    /// Plays `data` for the object attachment `id`; false where it is no
    /// metafile this can draw.
    @discardableResult
    static func register(_ data: Data, for id: String) -> Bool {
        guard let played = Metafile(data, id: id) else { return false }
        lock.lock()
        entries[id] = played
        lock.unlock()
        WriterCharts.installHooks()
        return true
    }

    static func has(_ attachment: ImageAttachment) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[attachment.id] != nil
    }

    static func paint(_ attachment: ImageAttachment, _ canvas: any Canvas, _ rect: Rect) -> Bool {
        lock.lock()
        let played = entries[attachment.id]
        lock.unlock()
        guard let played else { return false }
        played.paint(canvas, in: rect, image: { image($0) }, font: OfficeFonts.drawn)
        return true
    }
}

/// The lines and boxes of a drawing group (`wpg:wgp`) in Writer — or of
/// one shape alone that the layout's own outline does not draw — drawn
/// through `RichLayout.objectPainter` by the attachment's id, each at its
/// own place in the group; the group's text boxes are set by the layout
/// (`RichTextBox.parts`). The group was drawn as its first child alone,
/// stretched over the whole of it: zh-06c46ba9's tree of labelled boxes,
/// whose first child is a connector, printed as one diagonal line across
/// the figure and boxes with no edges.
enum WriterGroups {
    private struct Shape {
        var rect: Rect
        var fill: Color?
        var line: Color?
        var lineWidth: Double
        /// A straight line, from corner to corner; else `geometry`.
        var isLine: Bool
        /// A line from the bottom left to the top right (flipped one way).
        var rising: Bool
        var geometry: FreeformGeometry?
        var rotation: Double
        var flipH: Bool
        var flipV: Bool
        var headEnd: LineEnd?
        var tailEnd: LineEnd?
        /// Its line's dash (`SlidePainter.dashPattern`'s names), nil solid.
        var dash: String? = nil
        /// A picture's bytes and its decode key: drawn over its box.
        var picture: (key: String, data: Data)? = nil
        /// WordArt (a VML textpath): its text fitted to the box.
        var wordArt: WordArtText? = nil
        var drawingWordArt: DrawingWordArt? = nil
    }
    /// A VML textpath — Word's WordArt — drawn as Slides draws WordArt
    /// (`WordArt`): each line stretched to the shape's box by its warp, in
    /// the textpath's face, the shape's fill and outline, and its shadow.
    private struct WordArtText {
        var lines: [String]
        var warp: TextWarp
        var family: String
        var bold: Bool
        var italic: Bool
        /// The letters' colour, under `look`'s gradient where it has one.
        var color: Color
        var look: RunLook?
        var shadow: WordArt.Shadow?
        var alignment: ParagraphAlignment
        /// The textpath's own size, in points (`font-size`), and whether
        /// it is fitted to its path (`fitshape`/`fitpath`): text set
        /// along an arch keeps its size, or runs the arc's length.
        var size: Double = 36
        var fitsPath = false
    }
    /// VML's text shapes (`o:spt` 136 to 175), in the order DrawingML's
    /// text warps take them.
    private static let _vmlTextWarps: [String] = [
        "textPlain", "textStop", "textTriangle", "textTriangleInverted", "textChevron", "textChevronInverted",
        "textRingInside", "textRingOutside", "textArchUp", "textArchDown", "textCircle", "textButton",
        "textArchUpPour", "textArchDownPour", "textCirclePour", "textButtonPour", "textCurveUp", "textCurveDown",
        "textCascadeUp", "textCascadeDown", "textWave1", "textWave2", "textDoubleWave1", "textWave4",
        "textInflate", "textDeflate", "textInflateBottom", "textDeflateBottom", "textInflateTop", "textDeflateTop",
        "textDeflateInflate", "textDeflateInflateDeflate", "textFadeRight", "textFadeLeft", "textFadeUp", "textFadeDown",
        "textSlantUp", "textSlantDown", "textCanUp", "textCanDown"]
    private struct Entry {
        let width: Double
        let height: Double
        let shapes: [Shape]
    }
    private nonisolated(unsafe) static var entries: [String: Entry] = [:]
    private static let lock = RegistryLock()
    private nonisolated(unsafe) static var decoded: [String: Image] = [:]
    private nonisolated(unsafe) static var decoding: Set<String> = []

    /// Whether a group's picture is still being decoded.
    static var hasPendingImages: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !decoding.isEmpty
    }

    /// A group's picture, decoded once; nil while it decodes.
    private static func image(_ key: String, _ data: Data) -> Image? {
        lock.lock()
        defer { lock.unlock() }
        if let image = decoded[key] { return image }
        guard !decoding.contains(key), !data.isEmpty else { return nil }
        decoding.insert(key)
        let bytes = [UInt8](data)
        Task { @MainActor in
            var image: Image? = nil
            if let codec = try? await instantiateImageCodec(bytes) {
                image = (try? await codec.getNextFrame())?.image
                codec.dispose()
            }
            lock.lock()
            decoding.remove(key)
            if let image { decoded[key] = image }
            lock.unlock()
        }
        return nil
    }

    /// DrawingML WordArt retains Word's resolved paragraph/run styles;
    /// the ordinary text-box overlay must not draw these runs a second time.
    struct DrawingWordArt {
        var warp: TextWarp
        var paragraphs: [RichParagraph]
        var styles: RichStyleSheet
        var insets: EdgeInsets
    }

    /// Fitted text between two envelope curves. Path-based/unsupported
    /// warps, vertical text and boxes containing objects keep the text-box path.
    static func textWarp(_ shape: XNode) -> TextWarp? {
        guard let body = shape.first("wps:bodyPr"),
              ["1", "true"].contains(body["fromWordArt"] ?? ""),
              body["vert"] == nil || body["vert"] == "horz",
              let w = body.first("a:prstTxWarp"), let preset = w["prst"],
              let content = shape.first("wps:txbx")?.first("w:txbxContent"),
              !content.all("w:p").isEmpty,
              !["w:tbl", "w:drawing", "w:pict", "w:object"].contains(where: { content.descendant($0) != nil }),
              let xfrm = shape.first("wps:spPr")?.first("a:xfrm"),
              (Double(xfrm.first("a:ext")?["cx"] ?? "") ?? 0) > 0,
              (Double(xfrm.first("a:ext")?["cy"] ?? "") ?? 0) > 0 else { return nil }
        let adjustments = (w.first("a:avLst")?.all("a:gd") ?? []).compactMap { gd -> Double? in
            guard let formula = gd["fmla"], formula.hasPrefix("val ") else { return nil }
            return Double(formula.dropFirst(4))
        }
        let warp = TextWarp(preset: preset, adjust: adjustments, xml: PptxXML.serialize(w))
        return WordArt.envelope(warp) != nil ? warp : nil
    }

    /// Reads the shapes of `group` (a `wpg:wgp`) — straight lines, and
    /// every preset `PresetGeometry` defines — in points from its top
    /// left, for the object attachment `id`; false where it has none to
    /// draw.
    @discardableResult
    static func register(_ group: XNode, for id: String, themePart: Data?, wordArt: [ObjectIdentifier: DrawingWordArt] = [:],
                         picture: (String) -> Data? = { _ in nil }) -> Bool {
        let theme = PptxTheme(themePart.flatMap { XNode.parse($0) })
        let colors = ColorContext(theme: theme)
        // (Or one shape alone, a `wps:wsp`: a group of itself.)
        let lone = group.name == "wps:wsp"
        guard let top = (lone ? group.first("wps:spPr") : group.first("wpg:grpSpPr"))?.first("a:xfrm") else { return false }
        func number(_ n: XNode?, _ key: String) -> Double { Double(n?[key] ?? "") ?? 0 }
        let width = number(top.first("a:ext"), "cx"), height = number(top.first("a:ext"), "cy")
        // (A level or upright line is no width or no height: zh-e2dc9dce's
        // arrowed connectors, `cx="0"`, drew nothing.)
        guard width > 0 || height > 0, width >= 0, height >= 0 else { return false }
        // Child space → the group's, in EMU from its top left.
        typealias Map = (Rect) -> Rect
        func map(_ xfrm: XNode, outer: @escaping Map) -> Map {
            let off = xfrm.first("a:off"), ext = xfrm.first("a:ext")
            let chOff = xfrm.first("a:chOff"), chExt = xfrm.first("a:chExt")
            let kx = number(chExt, "cx") > 0 ? number(ext, "cx") / number(chExt, "cx") : 1
            let ky = number(chExt, "cy") > 0 ? number(ext, "cy") / number(chExt, "cy") : 1
            let ox = number(off, "x"), oy = number(off, "y"), cx = number(chOff, "x"), cy = number(chOff, "y")
            return { r in
                outer(Rect.fromLTWH(ox + (r.left - cx) * kx, oy + (r.top - cy) * ky, r.width * kx, r.height * ky))
            }
        }
        // The outermost group's own offset is where it stands, not a
        // place inside it.
        let root = map(top) { r in r.shift(Offset(-number(top.first("a:off"), "x"), -number(top.first("a:off"), "y"))) }
        var shapes: [Shape] = []
        func walk(_ children: [XNode], _ place: @escaping Map) {
            for child in children {
                switch child.name {
                case "wpg:grpSp":
                    if let xfrm = child.first("wpg:grpSpPr")?.first("a:xfrm") { walk(child.children, map(xfrm, outer: place)) }
                case "pic:pic":
                    // (A picture in the group, drawn over its box: lo
                    // tdf126426's page-size photo under a white text box.)
                    guard let rid = child.first("pic:blipFill")?.first("a:blip")?["r:embed"], let data = picture(rid),
                          let xfrm = child.first("pic:spPr")?.first("a:xfrm") else { continue }
                    let at = place(Rect.fromLTWH(number(xfrm.first("a:off"), "x"), number(xfrm.first("a:off"), "y"),
                                                 number(xfrm.first("a:ext"), "cx"), number(xfrm.first("a:ext"), "cy")))
                    shapes.append(Shape(rect: Rect.fromLTWH(at.left / 12700, at.top / 12700, at.width / 12700, at.height / 12700),
                                        fill: nil, line: nil, lineWidth: 0, isLine: false, rising: false, geometry: nil,
                                        rotation: 0, flipH: false, flipV: false, headEnd: nil, tailEnd: nil,
                                        picture: (id + "#" + String(shapes.count), data)))
                case "wps:wsp":
                    // (A freeform too, `a:custGeom`: zh-ae2dd08d's flowcharts
                    // draw their boxes and diamonds so, Word's print each with
                    // its edges, ours with none.)
                    let art = wordArt[ObjectIdentifier(child)]
                    let custom = child.first("wps:spPr")?.first("a:custGeom")
                    guard let sp = child.first("wps:spPr"), let prst = sp.first("a:prstGeom")?["prst"] ?? (custom != nil ? "" : art != nil ? "rect" : nil),
                          let xfrm = sp.first("a:xfrm") else { continue }
                    let at = place(Rect.fromLTWH(number(xfrm.first("a:off"), "x"), number(xfrm.first("a:off"), "y"),
                                                 number(xfrm.first("a:ext"), "cx"), number(xfrm.first("a:ext"), "cy")))
                    let style = child.first("wps:style")
                    func styled(_ ref: String) -> (Color?, Int) {
                        guard let r = style?.first(ref), let idx = Int(r["idx"] ?? ""), idx > 0 else { return (nil, 0) }
                        return (colors.color(in: r), idx)
                    }
                    let isLine = ["line", "straightConnector1"].contains(prst)
                    let geometry: FreeformGeometry?
                    if isLine { geometry = nil }
                    else if let custom { geometry = FreeformGeometry.parse(custom, width: max(1, at.width), height: max(1, at.height)) }
                    else {
                        geometry = PresetGeometry.geometry(prst, width: max(1, at.width), height: max(1, at.height),
                                                           adjustments: sp.first("a:prstGeom").map { PresetGeometry.adjustments($0) } ?? [:])
                    }
                    guard isLine || geometry != nil || art != nil else { continue }
                    var fill: Color? = nil
                    if !isLine {
                        if sp.first("a:noFill") != nil { fill = nil }
                        else if let f = sp.first("a:solidFill") { fill = colors.color(in: f) ?? f.first("a:sysClr")?["lastClr"].flatMap { Int64($0, radix: 16) }.map { Color(0xFF00_0000 | $0) } }
                        else { fill = styled("a:fillRef").0 }
                    }
                    let ln = sp.first("a:ln")
                    var line: Color? = nil
                    var lineWidth = (ln?["w"]).flatMap { Double($0) }.map { $0 / 12700 }
                    // (A system colour by its last value, and a fill named but
                    // not read black, as the outline drew it: zh-e2dc9dce's
                    // connectors say `a:sysClr val="windowText"`.)
                    func solid(_ f: XNode) -> Color? {
                        if let c = colors.color(in: f) { return c }
                        if let v = f.first("a:sysClr")?["lastClr"], let n = Int64(v, radix: 16) { return Color(0xFF00_0000 | n) }
                        return Color(0xFF000000)
                    }
                    if ln?.first("a:noFill") != nil { line = nil }
                    else if let f = ln?.first("a:solidFill") { line = solid(f) }
                    else {
                        let (c, idx) = styled("a:lnRef")
                        line = c
                        if lineWidth == nil, idx > 0, idx <= theme.lineWidths.count { lineWidth = theme.lineWidths[idx - 1] }
                    }
                    guard fill != nil || line != nil || art != nil else { continue }
                    let flipH = xfrm["flipH"] == "1", flipV = xfrm["flipV"] == "1"
                    // (A line runs from its box's top left, each flip taking
                    // that corner across; the painter runs a rising line from
                    // its bottom left, a falling one from its top left. So the
                    // head is the painter's start only where the line starts
                    // there: zh-2e7ef069's "flipH" connectors run down, their
                    // tail arrows at the foot, where ours stood at the top.)
                    let head = PptxReader.lineEnd(ln?.first("a:headEnd")), tail = PptxReader.lineEnd(ln?.first("a:tailEnd"))
                    let rising = flipH != flipV
                    let fromStart = !isLine || (rising ? (!flipH && flipV) : (!flipH && !flipV))
                    shapes.append(Shape(rect: Rect.fromLTWH(at.left / 12700, at.top / 12700, at.width / 12700, at.height / 12700),
                                        fill: fill, line: line, lineWidth: lineWidth ?? 0.75, isLine: isLine, rising: rising,
                                        geometry: geometry, rotation: (Double(xfrm["rot"] ?? "") ?? 0) / 60000,
                                        flipH: flipH, flipV: flipV,
                                        headEnd: fromStart ? head : tail, tailEnd: fromStart ? tail : head,
                                        dash: PptxReader.dash(ln), drawingWordArt: art))
                default: continue
                }
            }
        }
        // (A lone shape's own offset is where it stands: its place is
        // its box.)
        if lone {
            walk([group]) { r in r.shift(Offset(-number(top.first("a:off"), "x"), -number(top.first("a:off"), "y"))) }
        } else {
            walk(group.children, root)
        }
        guard !shapes.isEmpty else { return false }
        lock.lock()
        entries[id] = Entry(width: width / 12700, height: height / 12700, shapes: shapes)
        lock.unlock()
        WriterCharts.installHooks()
        return true
    }

    // MARK: VML groups

    /// VML's shape types (`o:spt`) as the DrawingML presets they draw.
    private static let _vmlPresets: [Int: String] = [
        1: "rect", 2: "roundRect", 3: "ellipse", 4: "diamond", 5: "triangle", 6: "rtTriangle", 7: "parallelogram",
        8: "trapezoid", 9: "hexagon", 10: "octagon", 13: "rightArrow", 15: "homePlate", 66: "leftArrow", 67: "downArrow",
        68: "upArrow", 109: "flowChartProcess", 110: "flowChartDecision", 111: "flowChartInputOutput",
        112: "flowChartPredefinedProcess", 113: "flowChartInternalStorage", 114: "flowChartDocument",
        115: "flowChartMultidocument", 116: "flowChartTerminator", 117: "flowChartPreparation",
        118: "flowChartManualInput", 119: "flowChartManualOperation", 120: "flowChartConnector",
        176: "flowChartAlternateProcess", 202: "rect",
        33: "bentConnector2", 34: "bentConnector3", 35: "bentConnector4", 37: "curvedConnector2", 38: "curvedConnector3",
    ]
    /// Connectors: lines, never filled.
    private static let _vmlConnectors: Set<Int> = [20, 32, 33, 34, 35, 36, 37, 38, 39, 40]
    /// Connectors drawn as a straight line from corner to corner.
    private static let _vmlStraight: Set<Int> = [20, 32]

    /// Reads the shapes of a VML group (`v:group`) — lines (`v:line`),
    /// boxes and ovals, shapes of a known type (`o:spt`, `types` by id)
    /// and free paths (`path`) — in points from its top left, for the
    /// object attachment `id`; false where it has none to draw. Its text
    /// boxes' text is the layout's (`_vmlTextPlaces`); this draws their
    /// edges and fills.
    @discardableResult
    static func registerVML(_ group: XNode, types: [XNode], for id: String, picture: (String) -> Data? = { _ in nil }) -> Bool {
        func style(_ n: XNode) -> [String: String] {
            var out: [String: String] = [:]
            for pair in (n["style"] ?? "").split(separator: ";") {
                let kv = pair.split(separator: ":", maxSplits: 1)
                if kv.count == 2 { out[kv[0].trimmingWhitespace()] = String(kv[1]).trimmingWhitespace() }
            }
            return out
        }
        func pair(_ raw: String?, _ fallback: (Double, Double)) -> (Double, Double) {
            let v = (raw ?? "").split(separator: ",", omittingEmptySubsequences: false).map { Double($0.trimmingWhitespace()) }
            return (v.count > 0 ? v[0] ?? fallback.0 : fallback.0, v.count > 1 ? v[1] ?? fallback.1 : fallback.1)
        }
        func points(_ v: String?) -> Double? {
            guard var t = v?.trimmingWhitespace(), !t.isEmpty else { return nil }
            var k = 1.0
            for (unit, f) in [("pt", 1.0), ("px", 0.75), ("in", 72.0), ("cm", 72 / 2.54), ("mm", 72 / 25.4), ("emu", 1 / 12700.0)] where t.hasSuffix(unit) {
                t = String(t.dropLast(unit.count)); k = f; break
            }
            return Double(t).map { $0 * k }
        }
        func off(_ v: String?) -> Bool { v == "f" || v == "false" || v == "0" }
        let named: [String: Int64] = ["black": 0x000000, "white": 0xFFFFFF, "red": 0xFF0000, "green": 0x008000, "lime": 0x00FF00,
                                      "blue": 0x0000FF, "yellow": 0xFFFF00, "gray": 0x808080, "grey": 0x808080, "silver": 0xC0C0C0,
                                      "navy": 0x000080, "maroon": 0x800000, "purple": 0x800080, "teal": 0x008080, "olive": 0x808000,
                                      "aqua": 0x00FFFF, "fuchsia": 0xFF00FF, "windowText": 0x000000, "window": 0xFFFFFF]
        func color(_ v: String?) -> Color? {
            guard var t = v?.trimmingWhitespace(), !t.isEmpty else { return nil }
            if let b = t.firstIndex(of: " ") { t = String(t[..<b]) }
            if t.hasPrefix("#") {
                var hex = String(t.dropFirst())
                if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
                guard hex.count == 6, let n = Int64(hex, radix: 16) else { return nil }
                return Color(0xFF00_0000 | n)
            }
            return named[t].map { Color(0xFF00_0000 | $0) }
        }
        func arrow(_ kind: String?, _ w: String?, _ len: String?) -> LineEnd? {
            guard let kind, kind != "none" else { return nil }
            let map = ["block": "triangle", "classic": "stealth", "open": "arrow", "oval": "oval", "diamond": "diamond"]
            func size(_ v: String?) -> Double { v == "narrow" || v == "short" ? 2 : v == "wide" || v == "long" ? 5 : 3 }
            return LineEnd(kind: map[kind] ?? "triangle", width: size(w), length: size(len))
        }
        // (VML's dash names as DrawingML's, a list of numbers as its own
        // pattern: zh-6e6b9821's leaders "1 1", dotted in Word's print.)
        func dash(_ v: String?) -> String? {
            guard let v = v?.trimmingWhitespace(), !v.isEmpty, v != "solid" else { return nil }
            let names = ["shortdash": "sysDash", "shortdot": "sysDot", "shortdashdot": "sysDashDot", "shortdashdotdot": "sysDashDotDot",
                         "dot": "dot", "dash": "dash", "longdash": "lgDash", "dashdot": "dashDot", "longdashdot": "lgDashDot",
                         "longdashdotdot": "lgDashDotDot"]
            if let n = names[v.lowercased()] { return n }
            let nums = v.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
            return nums.count >= 2 ? "cust:" + nums.map { String($0) }.joined(separator: ",") : nil
        }
        /// A VML fraction: "0.5", ".5", "50%", or 65536ths ("32768f").
        func fraction(_ v: String?) -> Double? {
            guard let t = v?.trimmingWhitespace(), !t.isEmpty else { return nil }
            if t.hasSuffix("f") { return Double(t.dropLast()).map { $0 / 65536 } }
            if t.hasSuffix("%") { return Double(t.dropLast()).map { $0 / 100 } }
            return Double(t)
        }
        /// A shape's textpath as WordArt, where it has one switched on.
        func wordArt(_ shape: XNode, type: XNode?, spt: Int?, fillNode: XNode?, line: Color?, weight: Double) -> WordArtText? {
            guard let path = shape.first("v:textpath"), let text = path["string"], !text.isEmpty,
                  !off(path["on"] ?? type?.first("v:textpath")?["on"] ?? "f"),
                  let spt, (136 ... 175).contains(spt) else { return nil }
            let st = style(path)
            let family = (st["font-family"] ?? "Arial").trimming(charactersIn: "\"' ")
            let filled = !(off(shape["filled"]) || off(fillNode?["on"]))
            let opacity = fraction(fillNode?["opacity"]) ?? 1
            func faded(_ c: Color) -> Color { c.withAlpha(Int((Double(c.alpha) * max(0, min(1, opacity))).rounded())) }
            let base = faded(color(fillNode?["color"]) ?? color(shape["fillcolor"]) ?? Color(0xFFFFFFFF))
            var look = RunLook()
            look.noFill = !filled
            if let line { look.outline = line; look.outlineWidth = weight }
            if filled, let kind = fillNode?["type"], kind.hasPrefix("gradient") {
                // Its stops, from `colors` ("pos color;…") or the two
                // colours; the angle VML's (0 down the shape, -90 right to
                // left), as DrawingML's clockwise from left to right.
                var stops: [SlideFill.GradientStop] = []
                for item in (fillNode?["colors"] ?? "").split(separator: ";") {
                    let kv = item.trimmingWhitespace().split(separator: " ", maxSplits: 1)
                    if kv.count == 2, let at = fraction(String(kv[0])), let c = color(String(kv[1])) {
                        stops.append(SlideFill.GradientStop(position: at, color: faded(c)))
                    }
                }
                if stops.count < 2 {
                    stops = [SlideFill.GradientStop(position: 0, color: base),
                             SlideFill.GradientStop(position: 1, color: faded(color(fillNode?["color2"]) ?? Color(0xFFFFFFFF)))]
                }
                // A focus at the far end runs it backwards; one half way, out and back.
                let focus = fraction(fillNode?["focus"]) ?? 0
                if abs(focus) > 0.75 { stops = stops.reversed().map { SlideFill.GradientStop(position: 1 - $0.position, color: $0.color) } }
                else if abs(focus) > 0.25 {
                    let half = stops.map { SlideFill.GradientStop(position: $0.position / 2, color: $0.color) }
                    stops = half + half.reversed().map { SlideFill.GradientStop(position: 1 - $0.position, color: $0.color) }
                }
                var fill = SlideFill()
                fill.stops = stops
                fill.angle = 90 - (Double(fillNode?["angle"] ?? "0") ?? 0)
                fill.even = true
                look.fill = fill
            }
            var shadow: WordArt.Shadow? = nil
            if let sh = shape.first("v:shadow"), !off(sh["on"] ?? "f") {
                let o = (sh["offset"] ?? "").split(separator: ",", omittingEmptySubsequences: false).map { points(String($0)) }
                var cast = WordArt.Shadow(color: (color(sh["color"]) ?? Color(0xFF808080)).withOpacity(max(0, min(1, fraction(sh["opacity"]) ?? 1))))
                cast.offset = Offset((o.count > 0 ? o[0] : nil) ?? 2, (o.count > 1 ? o[1] : nil) ?? 2)
                if sh["type"] == "perspective" {
                    let m = (sh["matrix"] ?? "").split(separator: ",", omittingEmptySubsequences: false).map { fraction(String($0)) }
                    func at(_ i: Int, _ d: Double) -> Double { (i < m.count ? m[i] : nil) ?? d }
                    cast.matrix = (at(0, 1), at(1, 0), at(2, 0), at(3, 1))
                    let origin = pair(sh["origin"], (0, 0))
                    cast.origin = Offset(origin.0, origin.1)
                }
                shadow = cast
            }
            let align: ParagraphAlignment = {
                switch st["v-text-align"] {
                case "left": return .left
                case "right": return .right
                default: return .center
                }
            }()
            return WordArtText(lines: text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init), warp: TextWarp(preset: _vmlTextWarps[spt - 136], xml: ""),
                               family: family, bold: st["font-weight"] == "bold", italic: st["font-style"] == "italic",
                               color: base, look: look.isPlain ? nil : look, shadow: shadow, alignment: align,
                               size: points(st["font-size"]) ?? 36,
                               fitsPath: !off(path["fitshape"] ?? "f") || !off(path["fitpath"] ?? "f"))
        }
        let g = style(group)
        guard let gw = points(g["width"]), let gh = points(g["height"]), gw > 0, gh > 0 else { return false }
        var shapes: [Shape] = []
        typealias Map = (Rect) -> Rect
        func walk(_ group: XNode, _ map: @escaping Map) {
            let origin = pair(group["coordorigin"], (0, 0)), size = pair(group["coordsize"], (1000, 1000))
            guard size.0 > 0, size.1 > 0 else { return }
            for child in group.children {
                let sh = style(child)
                let stroke = child.first("v:stroke"), fillNode = child.first("v:fill")
                let line: Color? = (off(child["stroked"]) || off(stroke?["on"])) ? nil : (color(stroke?["color"]) ?? color(child["strokecolor"]) ?? Color(0xFF000000))
                let weight = points(child["strokeweight"]) ?? points(stroke?["weight"]) ?? 0.75
                if child.name == "v:line" {
                    guard line != nil, child["from"] != nil || child["to"] != nil else { continue }
                    var a = pair(child["from"], (0, 0)), b = pair(child["to"], (0, 0))
                    // (A flip takes the ends across: zh-6e6b9821's dashed
                    // leader "flip:y" from 8393,42687 to 8993,43122 rises to
                    // the right in Word's print.)
                    let lineFlip = sh["flip"] ?? ""
                    if lineFlip.containsSubstring("x") { (a.0, b.0) = (b.0, a.0) }
                    if lineFlip.containsSubstring("y") { (a.1, b.1) = (b.1, a.1) }
                    let pa = map(Rect.fromLTWH(a.0 - origin.0, a.1 - origin.1, 0, 0)).topLeft
                    let pb = map(Rect.fromLTWH(b.0 - origin.0, b.1 - origin.1, 0, 0)).topLeft
                    let r = Rect.fromLTRB(min(pa.dx, pb.dx), min(pa.dy, pb.dy), max(pa.dx, pb.dx), max(pa.dy, pb.dy))
                    let rising = (pb.dx - pa.dx) * (pb.dy - pa.dy) < 0
                    // (The painter runs a line from its left end: the arrow
                    // at `from` is its head when `from` is that end.)
                    let fromStart = rising ? (pa.dx <= pb.dx) : (pa.dx < pb.dx || (pa.dx == pb.dx && pa.dy <= pb.dy))
                    let start = arrow(stroke?["startarrow"], stroke?["startarrowwidth"], stroke?["startarrowlength"])
                    let end = arrow(stroke?["endarrow"], stroke?["endarrowwidth"], stroke?["endarrowlength"])
                    shapes.append(Shape(rect: r, fill: nil, line: line, lineWidth: weight, isLine: true, rising: rising, geometry: nil,
                                        rotation: 0, flipH: false, flipV: false,
                                        headEnd: fromStart ? start : end, tailEnd: fromStart ? end : start, dash: dash(stroke?["dashstyle"])))
                    continue
                }
                guard let x = sh["left"].flatMap({ Double($0) }), let y = sh["top"].flatMap({ Double($0) }),
                      let w = sh["width"].flatMap({ Double($0) }), let h = sh["height"].flatMap({ Double($0) }) else { continue }
                let r = map(Rect.fromLTWH(x - origin.0, y - origin.1, w, h))
                if child.name == "v:group" {
                    let inner = pair(child["coordsize"], (1000, 1000))
                    guard inner.0 > 0, inner.1 > 0 else { continue }
                    walk(child) { q in Rect.fromLTWH(r.left + q.left * r.width / inner.0, r.top + q.top * r.height / inner.1,
                                                     q.width * r.width / inner.0, q.height * r.height / inner.1) }
                    continue
                }
                // What it is: a known type, else its kind, else its path.
                let typeID = child["type"].map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
                let type = typeID.flatMap { id in types.first(where: { $0["id"] == id }) }
                let spt = Int(child["o:spt"] ?? type?["o:spt"] ?? "") ?? typeID.flatMap { t in t.hasPrefix("_x0000_t") ? Int(t.dropFirst(8)) : nil }
                // (A picture is not a line drawing: one whose `v:imagedata`
                // names a picture. WPS writes an empty one into every shape
                // — zh-e9f256c1's whole flowchart, which printed as text.)
                // (A picture in the group — zh-7773163d's footer logo, a
                // PNG under its text — drawn over its box, a raster one.)
                if let data = child.first("v:imagedata").flatMap({ $0["r:id"] ?? $0["o:relid"] }).flatMap(picture) {
                    shapes.append(Shape(rect: r, fill: nil, line: nil, lineWidth: 0, isLine: false, rising: false, geometry: nil,
                                        rotation: 0, flipH: false, flipV: false, headEnd: nil, tailEnd: nil,
                                        picture: (id + "#" + String(shapes.count), data)))
                    continue
                }
                if spt == 75 && child.first("v:textbox") == nil { continue }
                let path = child["path"] ?? (spt == nil ? type?["path"] : nil)
                let straight = spt.map { _vmlStraight.contains($0) } ?? false
                let filled = !(off(child["filled"]) || off(fillNode?["on"])) && !(spt.map { _vmlConnectors.contains($0) } ?? false)
                let fill: Color? = filled ? (color(fillNode?["color"]) ?? color(child["fillcolor"]) ?? Color(0xFFFFFFFF)) : nil
                // (In degrees, or in 65536ths of one with an "f": WPS writes
                // its turned connectors "rotation:-5898240f", -90.)
                let rotation: Double = {
                    guard let raw = sh["rotation"]?.trimmingWhitespace() else { return 0 }
                    if raw.hasSuffix("f") { return (Double(raw.dropLast()) ?? 0) / 65536 }
                    return Double(raw) ?? 0
                }()
                let flip = sh["flip"] ?? ""
                let flipH = flip.containsSubstring("x"), flipV = flip.containsSubstring("y")
                let pt = Rect.fromLTWH(r.left, r.top, r.width, r.height)
                let start = arrow(stroke?["startarrow"], stroke?["startarrowwidth"], stroke?["startarrowlength"])
                let end = arrow(stroke?["endarrow"], stroke?["endarrowwidth"], stroke?["endarrowlength"])
                // (WordArt: WordWithAttachments' three titles, drawn as
                // nothing — their path is all formulas.)
                if let art = wordArt(child, type: type, spt: spt, fillNode: fillNode, line: line, weight: weight) {
                    shapes.append(Shape(rect: pt, fill: nil, line: nil, lineWidth: 0, isLine: false, rising: false, geometry: nil,
                                        rotation: rotation, flipH: flipH, flipV: flipV, headEnd: nil, tailEnd: nil, wordArt: art))
                    continue
                }
                if straight {
                    guard line != nil else { continue }
                    // (From its box's top left to its bottom right, each flip
                    // taking that corner across: a "flip:x" line runs from
                    // the top right down — zh-e9f256c1's arrows between its
                    // steps, "flip:x" and one wide, point down. The painter
                    // runs a rising line from its bottom left, a falling one
                    // from its top left: the arrow at the line's start is the
                    // painter's head where the start is that end.)
                    let rising = flipH != flipV
                    let startsLeft = !flipH, startsTop = !flipV
                    let fromStart = rising ? (startsLeft && !startsTop) : (startsLeft && startsTop)
                    shapes.append(Shape(rect: pt, fill: nil, line: line, lineWidth: weight, isLine: true, rising: rising,
                                        geometry: nil, rotation: rotation, flipH: flipH, flipV: flipV,
                                        headEnd: fromStart ? start : end, tailEnd: fromStart ? end : start, dash: dash(stroke?["dashstyle"])))
                    continue
                }
                var geometry: FreeformGeometry? = nil
                let preset: String? = {
                    switch child.name {
                    case "v:rect": return "rect"
                    case "v:roundrect": return "roundRect"
                    case "v:oval": return "ellipse"
                    default: return spt.flatMap { _vmlPresets[$0] }
                    }
                }()
                if let preset, path == nil || spt != nil {
                    geometry = PresetGeometry.geometry(preset, width: max(1, pt.width * 12700), height: max(1, pt.height * 12700), adjustments: [:])
                    // (An elbow, `bentConnector2`: across its top, then down
                    // its right side — zh-e9f256c1's return line.)
                    if geometry == nil, spt == 33 {
                        geometry = _vmlPath("m0,0l21600,0,21600,21600e", origin: (0, 0), size: (21600, 21600), width: pt.width, height: pt.height)
                    }
                } else if let path {
                    let cs = pair(child["coordsize"] ?? type?["coordsize"], (21600, 21600)), co = pair(child["coordorigin"], (0, 0))
                    geometry = _vmlPath(path, origin: co, size: cs, width: pt.width, height: pt.height)
                }
                guard let geometry, fill != nil || line != nil else { continue }
                // (Arrows only on a line: a connector, or a path left open.
                // zh-6e6b9821's side notes are text boxes whose stroke says
                // `endarrow`, and Word draws them as plain boxes.)
                let open = (spt.map { _vmlConnectors.contains($0) } ?? false) || (path.map { !$0.containsSubstring("x") } ?? false)
                shapes.append(Shape(rect: pt, fill: fill, line: line, lineWidth: weight, isLine: false, rising: false,
                                    geometry: geometry, rotation: rotation, flipH: flipH, flipV: flipV,
                                    headEnd: open ? start : nil, tailEnd: open ? end : nil, dash: dash(stroke?["dashstyle"])))
            }
        }
        let size = pair(group["coordsize"], (1000, 1000))
        guard size.0 > 0, size.1 > 0 else { return false }
        walk(group) { r in Rect.fromLTWH(r.left * gw / size.0, r.top * gh / size.1, r.width * gw / size.0, r.height * gh / size.1) }
        guard !shapes.isEmpty else { return false }
        lock.lock()
        entries[id] = Entry(width: gw, height: gh, shapes: shapes)
        lock.unlock()
        WriterCharts.installHooks()
        return true
    }

    /// A VML shape alone (`v:rect`, `v:roundrect`, `v:oval`, `v:shape`)
    /// as a group of itself: its edges and fill over its whole box —
    /// zh-7773163d's p35 steps, framed text boxes with no group, printed
    /// as their text alone.
    @discardableResult
    static func registerVMLShape(_ shape: XNode, types: [XNode], for id: String) -> Bool {
        var st: [String: String] = [:]
        for pair in (shape["style"] ?? "").split(separator: ";") {
            let kv = pair.split(separator: ":", maxSplits: 1)
            if kv.count == 2 { st[kv[0].trimmingWhitespace()] = String(kv[1]).trimmingWhitespace() }
        }
        func pt(_ v: String?) -> Double? {
            guard var t = v?.trimmingWhitespace(), !t.isEmpty else { return nil }
            var k = 1.0
            for (unit, f) in [("pt", 1.0), ("px", 0.75), ("in", 72.0), ("cm", 72 / 2.54), ("mm", 72 / 25.4)] where t.hasSuffix(unit) {
                t = String(t.dropLast(unit.count)); k = f; break
            }
            return Double(t).map { $0 * k }
        }
        guard let w = pt(st["width"]), let h = pt(st["height"]), w > 0, h > 0 else { return false }
        // Its own box in hundredths of a point, the group's frame the same.
        let cw = Int((w * 100).rounded()), ch = Int((h * 100).rounded())
        var keep = st.filter { ["rotation", "flip"].contains($0.key) }.map { "\($0.key):\($0.value)" }
        keep += ["left:0", "top:0", "width:\(cw)", "height:\(ch)"]
        var attrs = shape.attrs
        attrs["style"] = keep.joined(separator: ";")
        let copy = XNode(name: shape.name, attrs: attrs)
        copy.children = shape.children
        let frame = XNode(name: "v:group", attrs: ["style": "width:\(w)pt;height:\(h)pt", "coordorigin": "0,0", "coordsize": "\(cw),\(ch)"])
        frame.children = [copy]
        return registerVML(frame, types: types, for: id)
    }

    /// A VML path (`m x,y l x,y … c … x e`, and their relative `t r v`)
    /// as a freeform in a box `width` by `height` points, its numbers in
    /// the shape's `coordorigin`/`coordsize` space.
    private static func _vmlPath(_ path: String, origin: (Double, Double), size: (Double, Double), width: Double, height: Double) -> FreeformGeometry? {
        guard size.0 > 0, size.1 > 0 else { return nil }
        var tokens: [String] = []
        var cur = ""
        for ch in path {
            if ch.isLetter { if !cur.isEmpty { tokens.append(cur); cur = "" }; tokens.append(String(ch)) }
            else if ch == "," || ch == " " { if !cur.isEmpty { tokens.append(cur) }; cur = "" ; if ch == "," { tokens.append(",") } }
            else if ch == "-", !cur.isEmpty, cur != "-" { tokens.append(cur); cur = "-" }
            else { cur.append(ch) }
        }
        if !cur.isEmpty { tokens.append(cur) }
        // Numbers, an empty slot (",,") standing for 0.
        var xml = "<a:custGeom xmlns:a=\"a\"><a:pathLst><a:path w=\"\(Int(size.0))\" h=\"\(Int(size.1))\">"
        var i = 0, cmd = "", pos = (0.0, 0.0), open = false, any = false
        func numbers(_ n: Int) -> [Double]? {
            var out: [Double] = []
            var expectValue = true
            while out.count < n, i < tokens.count {
                let t = tokens[i]
                if t == "," { if expectValue { out.append(0) }; expectValue = true; i += 1; continue }
                guard let v = Double(t) else { break }
                out.append(v); expectValue = false; i += 1
            }
            if i < tokens.count, tokens[i] == ",", out.count == n { i += 1 }
            return out.count == n ? out : nil
        }
        func ptXML(_ p: (Double, Double)) -> String { "<a:pt x=\"\(Int((p.0 - origin.0).rounded()))\" y=\"\(Int((p.1 - origin.1).rounded()))\"/>" }
        while i < tokens.count {
            let t = tokens[i]
            if t.count == 1, t.first!.isLetter { cmd = t; i += 1 }
            switch cmd {
            case "m", "t":
                guard let v = numbers(2) else { i += 1; continue }
                pos = cmd == "m" ? (v[0], v[1]) : (pos.0 + v[0], pos.1 + v[1])
                xml += "<a:moveTo>\(ptXML(pos))</a:moveTo>"; open = true; any = true
            case "l", "r":
                guard let v = numbers(2) else { i += 1; continue }
                pos = cmd == "l" ? (v[0], v[1]) : (pos.0 + v[0], pos.1 + v[1])
                if !open { xml += "<a:moveTo>\(ptXML(pos))</a:moveTo>"; open = true } else { xml += "<a:lnTo>\(ptXML(pos))</a:lnTo>" }
                any = true
            case "c", "v":
                guard let v = numbers(6) else { i += 1; continue }
                let base = cmd == "c" ? (0.0, 0.0) : pos
                let p1 = (base.0 + v[0], base.1 + v[1]), p2 = (base.0 + v[2], base.1 + v[3]), p3 = (base.0 + v[4], base.1 + v[5])
                xml += "<a:cubicBezTo>\(ptXML(p1))\(ptXML(p2))\(ptXML(p3))</a:cubicBezTo>"; pos = p3; any = true
            case "x":
                xml += "<a:close/>"; open = false; cmd = ""
            case "e":
                cmd = ""
            case "n", "f", "s":   // nofill, nostroke, and an end of a subpath: not ours to draw here
                cmd = ""
            default:
                i += 1
            }
            if cmd == "" , i < tokens.count, !(tokens[i].count == 1 && tokens[i].first!.isLetter) { i += 1 }
        }
        xml += "</a:path></a:pathLst></a:custGeom>"
        guard any, let node = XNode.parse(Data(xml.utf8)) else { return nil }
        return FreeformGeometry.parse(node, width: max(1, width * 12700), height: max(1, height * 12700))
    }

    static func has(_ attachment: ImageAttachment) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[attachment.id] != nil
    }

    static func paint(_ attachment: ImageAttachment, _ canvas: any Canvas, _ rect: Rect, _ pxPerPt: Double) -> Bool {
        lock.lock()
        let entry = entries[attachment.id]
        lock.unlock()
        guard let entry else { return false }
        let sx = entry.width > 0 ? rect.width / entry.width : 1, sy = entry.height > 0 ? rect.height / entry.height : 1
        for s in entry.shapes {
            let r = Rect.fromLTWH(rect.left + s.rect.left * sx, rect.top + s.rect.top * sy, s.rect.width * sx, s.rect.height * sy)
            if let pic = s.picture {
                if let img = image(pic.key, pic.data) {
                    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, Double(img.width), Double(img.height)), r, Paint())
                }
                continue
            }
            canvas.save()
            // (Turned about its centre, and mirrored there: a shape's
            // outline is its preset's, unflipped.)
            let c = r.center
            canvas.translate(c.dx, c.dy)
            if s.rotation != 0 { canvas.rotate(s.rotation * .pi / 180) }
            if !s.isLine, s.flipH || s.flipV { canvas.scale(s.flipH ? -1 : 1, s.flipV ? -1 : 1) }
            canvas.translate(-c.dx, -c.dy)
            if let art = s.wordArt {
                // In the shape's own points: the outline and the shadow's
                // offset scale with it.
                let cjk = art.lines.contains { $0.unicodeScalars.contains { (0x2E80 ... 0x9FFF).contains($0.value) || (0xF900 ... 0xFAFF).contains($0.value) } }
                let family = cjk ? OfficeFonts.face(art.family, eastAsian: true)?.family ?? art.family : SlideFonts.resolve(art.family)
                // (A black face at its weight, so what it lacks falls back
                // to a heavy face too: Archivo Black has no Cyrillic, and
                // WordWithAttachments' "Мой текст здесь" came out light.)
                let black = art.family.trimmingWhitespace().lowercased().hasSuffix(" black")
                // (At its size on the canvas, which is in the page's
                // pixels: a bare 36 drew F13's arch, which keeps its
                // letters' size, 1.8pt high.)
                let base = Flutter.TextStyle(color: art.color, fontSize: art.size * (sx + sy) / 2, fontWeight: black ? .w900 : art.bold ? .bold : .normal,
                                             fontStyle: art.italic ? .italic : .normal, fontFamily: family)
                WordArt.paint(lines: art.lines.map { [($0, base, art.look)] }, alignment: art.alignment, warp: art.warp,
                              area: r, canvas: canvas, pxPerPt: (sx + sy) / 2, shadow: art.shadow, fitsPath: art.fitsPath)
                canvas.restore()
                continue
            }
            let stroke = Paint()
            stroke.style = .stroke
            stroke.isAntiAlias = true
            stroke.strokeWidth = max(1, s.lineWidth * pxPerPt)
            stroke.color = s.line ?? Color(0xFF000000)
            let base = max(s.lineWidth, 2) * pxPerPt
            if s.isLine {
                if s.line != nil {
                    let a0 = s.rising ? r.bottomLeft : r.topLeft, b0 = s.rising ? r.topRight : r.bottomRight
                    // (Stopping inside a filled head, as Slides draws it.)
                    func pulled(_ tip: Offset, from other: Offset, _ e: LineEnd?) -> Offset {
                        guard let e, ["triangle", "stealth"].contains(e.kind) else { return tip }
                        let d = Offset(tip.dx - other.dx, tip.dy - other.dy), len = (d.dx * d.dx + d.dy * d.dy).squareRoot()
                        guard len > 1e-6 else { return tip }
                        let back = min(len / 2, e.length * base * 0.8)
                        return Offset(tip.dx - d.dx / len * back, tip.dy - d.dy / len * back)
                    }
                    let p0 = pulled(a0, from: b0, s.headEnd), p1 = pulled(b0, from: a0, s.tailEnd)
                    if s.dash != nil {
                        let line = Path()
                        line.moveTo(p0.dx, p0.dy); line.lineTo(p1.dx, p1.dy)
                        canvas.drawPath(SlidePainter.dashed(line, s.dash, width: stroke.strokeWidth), stroke)
                    } else {
                        canvas.drawLine(p0, p1, stroke)
                    }
                    if let e = s.headEnd { SlidePainter.lineEnd(e, tip: a0, from: b0, base: base, paint: stroke, canvas) }
                    if let e = s.tailEnd { SlidePainter.lineEnd(e, tip: b0, from: a0, base: base, paint: stroke, canvas) }
                }
            } else if let g = s.geometry {
                if let fill = s.fill {
                    let p = Paint()
                    p.style = .fill
                    p.isAntiAlias = true
                    p.color = fill
                    canvas.drawPath(SlidePainter.combinedPath(g, r), p)
                }
                if s.line != nil {
                    for sub in g.subpaths where sub.stroke {
                        canvas.drawPath(SlidePainter.dashed(FreeformGeometry.path(sub, in: r), s.dash, width: stroke.strokeWidth), stroke)
                        if s.headEnd != nil || s.tailEnd != nil, let ends = SlidePainter.pathEnds(sub, in: r) {
                            if let e = s.headEnd { SlidePainter.lineEnd(e, tip: ends.start, from: ends.startFrom, base: base, paint: stroke, canvas) }
                            if let e = s.tailEnd { SlidePainter.lineEnd(e, tip: ends.end, from: ends.endFrom, base: base, paint: stroke, canvas) }
                        }
                    }
                }
            }
            if let art = s.drawingWordArt {
                let theme = RichTextTheme(fontFamily: OfficeFonts.sans)
                theme.pixelsPerPoint = (sx + sy) / 2
                theme.fontFamilyResolver = OfficeFonts.drawn
                theme.faceResolver = OfficeFonts.face
                let normal = art.styles[RichNamedStyle.normalId]?.char
                let lines = art.paragraphs.map { paragraph -> [(text: String, style: Flutter.TextStyle, look: RunLook?)] in
                    let units = Array(paragraph.text.utf16)
                    let named = art.styles.resolve(paragraph.style)
                    var offset = 0
                    var runs: [(text: String, style: Flutter.TextStyle, look: RunLook?)] = []
                    for run in paragraph.runs {
                        let end = min(units.count, offset + run.length)
                        let text = String(decoding: units[offset ..< end], as: UTF16.self)
                        offset = end
                        for ch in text {
                            let eastAsian = ch.unicodeScalars.contains {
                                (0x2E80 ... 0x9FFF).contains($0.value) || (0xF900 ... 0xFAFF).contains($0.value) || (0xFF00 ... 0xFFEF).contains($0.value)
                            }
                            let style = theme.textStyle(for: run.style, in: paragraph.style, named: named, normal: normal,
                                                        scale: 1, eastAsian: eastAsian)
                            runs.append((String(ch), style, nil))
                        }
                    }
                    return runs
                }
                let area = Rect.fromLTRB(r.left + art.insets.left * sx, r.top + art.insets.top * sy,
                                         r.right - art.insets.right * sx, r.bottom - art.insets.bottom * sy)
                WordArt.paint(lines: lines, alignment: art.paragraphs.first?.style.alignment ?? .left,
                              warp: art.warp, area: area, canvas: canvas, pxPerPt: (sx + sy) / 2, fitsInk: true)
            }
            canvas.restore()
        }
        return true
    }
}
