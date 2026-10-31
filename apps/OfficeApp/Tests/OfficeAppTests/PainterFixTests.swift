import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// Fixes from ranking this app's drawing against PowerPoint's over the
/// corpus (2026-10-09): path gradients, picture placement, mirrored
/// shapes, colour modifiers, the deck's own table styles.
final class PainterFixTests: XCTestCase {
    private let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
    private var colors: ColorContext {
        var t = PptxTheme(nil)
        t.colors = ["dk1": Color(0xFF000000), "lt1": Color(0xFFFFFFFF), "lt2": Color(0xFFE7E6E6), "accent1": Color(0xFF4472C4)]
        return ColorContext(theme: t)
    }

    func testAPathGradientRadiatesFromItsFillToRect() throws {
        let xml = "<a:gradFill \(ns)><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"FFFFFF\"/></a:gs><a:gs pos=\"100000\"><a:srgbClr val=\"000000\"/></a:gs></a:gsLst>"
            + "<a:path path=\"circle\"><a:fillToRect l=\"50000\" t=\"-80000\" r=\"50000\" b=\"180000\"/></a:path></a:gradFill>"
        let g = try XCTUnwrap(PptxReader.gradient(XNode.parse(Data(xml.utf8))!, colors: colors))
        XCTAssertEqual(g.path, .circle)
        XCTAssertEqual(g.fillTo.left, 0.5, accuracy: 1e-9)
        XCTAssertEqual(g.fillTo.top, -0.8, accuracy: 1e-9)
        XCTAssertEqual(g.fillTo.bottom, -0.8, accuracy: 1e-9, "b=180%: the rect's bottom is 80% above the top")
        XCTAssertEqual(g.stops.count, 2)
        // A linear one has no path; one with no stops is nothing at all.
        let lin = "<a:gradFill \(ns)><a:gsLst><a:gs pos=\"0\"><a:srgbClr val=\"FFFFFF\"/></a:gs><a:gs pos=\"100000\"><a:srgbClr val=\"000000\"/></a:gs></a:gsLst><a:lin ang=\"2700000\"/></a:gradFill>"
        XCTAssertNil(try XCTUnwrap(PptxReader.gradient(XNode.parse(Data(lin.utf8))!, colors: colors)).path)
        XCTAssertNil(PptxReader.gradient(XNode.parse(Data("<a:gradFill \(ns)><a:lin ang=\"0\"/></a:gradFill>".utf8))!, colors: colors))
    }

    /// A path gradient starts where its fill-to rectangle's insets put it
    /// in proportion (GeomLec1's l 65%, b 98% is the top right corner),
    /// and one of theme colours under modifiers blends evenly.
    func testAPathGradientStartsWhereItsInsetsBalance() throws {
        let focus = SlidePainter.pathFocus(Rect.fromLTRB(0.65, 0, 1, 0.02))
        XCTAssertEqual(focus.dx, 1, accuracy: 1e-9)
        XCTAssertEqual(focus.dy, 0, accuracy: 1e-9)
        let point = SlidePainter.pathFocus(Rect.fromLTRB(0.3, 0.7, 0.3, 0.7))
        XCTAssertEqual(point.dx, 0.3, accuracy: 1e-9, "a point is itself")
        XCTAssertEqual(point.dy, 0.7, accuracy: 1e-9)
        XCTAssertEqual(SlidePainter.pathFocus(Rect.fromLTRB(0, 0, 1, 1)).dx, 0.5, "no insets: the middle")
        func read(_ stops: String) throws -> SlideFill {
            try XCTUnwrap(PptxReader.gradient(XNode.parse(Data("<a:gradFill \(ns)><a:gsLst>\(stops)</a:gsLst><a:path path=\"circle\"/></a:gradFill>".utf8))!, colors: colors))
        }
        XCTAssertTrue(try read("<a:gs pos=\"0\"><a:schemeClr val=\"dk1\"><a:tint val=\"55000\"/></a:schemeClr></a:gs><a:gs pos=\"100000\"><a:schemeClr val=\"dk1\"/></a:gs>").even)
        XCTAssertFalse(try read("<a:gs pos=\"0\"><a:srgbClr val=\"FFFF00\"><a:alpha val=\"70000\"/></a:srgbClr></a:gs><a:gs pos=\"100000\"><a:srgbClr val=\"0070C0\"/></a:gs>").even)
    }

    func testAStretchedPicturesFillRectIsItsPlace() throws {
        let xml = "<a:blipFill \(ns)><a:blip/><a:stretch><a:fillRect l=\"55000\" t=\"56000\"/></a:stretch></a:blipFill>"
        let inset = PptxReader.stretchInset(XNode.parse(Data(xml.utf8))!)
        XCTAssertEqual(inset.left, 0.55, accuracy: 1e-9)
        XCTAssertEqual(inset.top, 0.56, accuracy: 1e-9)
        XCTAssertEqual(inset.right, 0)
        let r = SlidePainter.inset(Rect.fromLTWH(0, 0, 200, 100), inset)
        XCTAssertEqual(r.left, 110, accuracy: 1e-9)
        XCTAssertEqual(r.top, 56, accuracy: 1e-9)
        XCTAssertEqual(r.right, 200, accuracy: 1e-9)
        XCTAssertEqual(PptxReader.stretchInset(XNode.parse(Data("<a:blipFill \(ns)><a:stretch><a:fillRect/></a:stretch></a:blipFill>".utf8))!), .zero)
    }

    func testColourModifiers() throws {
        func mod(_ base: Color, _ mods: String) -> Color {
            ColorContext.modify(base, XNode.parse(Data("<a:schemeClr \(ns) val=\"x\">\(mods)</a:schemeClr>".utf8))!)
        }
        func parts(_ c: Color) -> (Int, Int, Int) { ((c.value >> 16) & 0xFF, (c.value >> 8) & 0xFF, c.value & 0xFF) }
        // satMod: a near-grey warms up (the cream of a theme's radial fill).
        let warm = parts(mod(Color(0xFFE7E6E6), "<a:satMod val=\"350000\"/>"))
        XCTAssertGreaterThan(warm.0 - warm.2, 2, "\(warm)")
        // A tint mixes in linear light: 50% of a dark grey is light, not the sRGB midpoint.
        let tint = parts(mod(Color(0xFF333333), "<a:tint val=\"50000\"/>"))
        XCTAssertGreaterThan(tint.0, 0xB0, "\(tint)")
        // Wrapped in gamma/invGamma (a converted .ppt's shade), it works on the sRGB values.
        let shade = parts(mod(Color(0xFFFFFFFF), "<a:gamma/><a:shade val=\"50000\"/><a:invGamma/>"))
        XCTAssertEqual(shade.0, 0x80, accuracy: 1)
        let linearShade = parts(mod(Color(0xFFFFFFFF), "<a:shade val=\"50000\"/>"))
        XCTAssertEqual(linearShade.0, 0xBC, accuracy: 2)
        // hueOff turns the hue (in 60000ths of a degree): red a third of the way round is green.
        let hue = parts(mod(Color(0xFFFF0000), "<a:hueOff val=\"7200000\"/>"))
        XCTAssertEqual(hue.1, 0xFF)
        XCTAssertEqual(hue.0, 0)
    }

    func testGreyscaleIsTheBlackToWhiteDuotone() throws {
        let blip = XNode.parse(Data("<a:blip \(ns)><a:grayscl/></a:blip>".utf8))!
        let (alpha, duotone) = PptxReader.blipEffects(blip, colors: colors)
        XCTAssertEqual(alpha, 1)
        XCTAssertEqual(duotone, [Color(0xFF000000), Color(0xFFFFFFFF)])
    }

    func testLucidaSansUnicodeIsNotMonospace() {
        XCTAssertEqual(OfficeFonts.substitute("Lucida Sans Unicode"), OfficeFonts.sans)
        XCTAssertEqual(OfficeFonts.substitute("Source Code Pro"), OfficeFonts.mono)
    }

    func testLucidaSansUnicodeIsSetAtItsOwnWidths() throws {
        // bug59058: its "SEER 9 Incidence…" note is two lines in Word's
        // print, one at Arial's widths. The widths are the /Widths of the
        // subset Word's print embeds.
        let face = try XCTUnwrap(OfficeFonts.face("Lucida Sans Unicode", eastAsian: false))
        let advances = try XCTUnwrap(face.advances)
        XCTAssertEqual(advances.count, 95, "U+0020 to U+007E")
        func width(_ c: Character) -> Double { advances[Int(c.asciiValue!) - 0x20] }
        XCTAssertEqual(width("0"), 0.632)
        XCTAssertEqual(width("7"), 0.632, "every digit alike")
        XCTAssertEqual(width(" "), 0.316)
        XCTAssertEqual(width("-"), 0.579)
        XCTAssertEqual(width("t"), 0.374)
        XCTAssertEqual(width("M"), 0.861)
        XCTAssertNil(OfficeFonts.face("Arial", eastAsian: false)?.advances, "Arial is its stand-in's own width")
    }

    func testJhengHeiUILightIsSetAtItsOwnWidths() throws {
        // zh-167ee06c's 華康雅風體W3(P), alternate JhengHei UI Light: Word's
        // print sets its digits and brackets in that face, its "1" 0.387 em
        // and the rest 0.558 (the /Widths of the subset it embeds), and
        // "…開始前一個月" is one line. At JhengHei's 0.58 — bold, 0.6 — the
        // "月" went to the next. The Light has no bold: Word emboldens it,
        // so its bold is the same widths and the face's spread.
        let face = try XCTUnwrap(OfficeFonts.face("Microsoft JhengHei UI Light", eastAsian: false))
        for table in [try XCTUnwrap(face.advances), try XCTUnwrap(face.boldAdvances)] {
            XCTAssertEqual(table.count, 95, "U+0020 to U+007E")
            func width(_ c: Character) -> Double { table[Int(c.asciiValue!) - 0x20] }
            XCTAssertEqual(width("1"), 0.387)
            XCTAssertEqual(width("2"), 0.558)
            XCTAssertEqual(width("4"), 0.575)
            XCTAssertEqual(width(" "), 0.296)
            XCTAssertEqual(width("("), 0.306)
            XCTAssertEqual(width("."), 0.239)
        }
        XCTAssertEqual(try XCTUnwrap(OfficeFonts.face("Microsoft JhengHei", eastAsian: false)?.advances)[0x31 - 0x20], 0.5796,
                       "JhengHei itself keeps its own")
    }

    func testYaHeiLightIsALineOfItsOwnWinAscent() throws {
        // msyhl.ttc's usWinAscent is 2080 in 2048 where regular's is 2167,
        // the same 536 under: Word for Windows steps zh-a7a889eb's 14pt
        // contents lines of 微软雅黑 Light (0.8125 auto, 17.3 before) 36.21
        // apart, 1.6605 em a line, where at regular's 1.715 ours took 36.83.
        let light = try XCTUnwrap(OfficeFonts.face("微软雅黑 Light", eastAsian: true))
        XCTAssertEqual(try XCTUnwrap(light.naturalHeight), 1.6605, accuracy: 0.0005)
        XCTAssertEqual(try XCTUnwrap(light.baseline), 1.2072, accuracy: 0.0005)
        XCTAssertEqual(try XCTUnwrap(OfficeFonts.face("Microsoft YaHei Light", eastAsian: true)?.naturalHeight), 1.6605, accuracy: 0.0005)
        XCTAssertEqual(try XCTUnwrap(OfficeFonts.face("微软雅黑", eastAsian: true)?.naturalHeight), 1.715, "regular keeps its own")
    }

    func testSegoeUISymbolIsALineOfItsOwnAscentAndDescent() throws {
        // seguisym.ttf: 2210 over and 514 under of 2048. zh-a7a889eb's
        // "☑12、…" cells (12pt, 0.8625 auto) step 17.16 in Word for
        // Windows' print; the clone's line under SimSun's set them 0.8 short.
        let face = try XCTUnwrap(OfficeFonts.face("Segoe UI Symbol", eastAsian: false))
        XCTAssertEqual(try XCTUnwrap(face.naturalHeight), 1.3301, accuracy: 0.0005)
        XCTAssertEqual(try XCTUnwrap(face.baseline), 1.0791, accuracy: 0.0005)
    }

    func testNunitoSansIsItsOwnWidthsAndLine() throws {
        // Office's cloud Nunito Sans, embedded in Word's prints of
        // zh-d97c5474: a 1.364 em line (hhea 1011/353 of 1000), and its
        // Light's space 0.251, "M" 0.849, "à" 0.522; its Bold's space 0.270.
        let light = try XCTUnwrap(OfficeFonts.face("Nunito Sans Light", eastAsian: false))
        XCTAssertEqual(try XCTUnwrap(light.naturalHeight), 1.364)
        XCTAssertEqual(try XCTUnwrap(light.baseline), 1.011)
        let a = try XCTUnwrap(light.advances)
        XCTAssertEqual(a.count, 95, "U+0020 to U+007E")
        XCTAssertEqual(a[0], 0.251)
        XCTAssertEqual(a[Int(Character("M").asciiValue!) - 0x20], 0.849)
        XCTAssertEqual(try XCTUnwrap(light.otherAdvances?[0xE0]), 0.522)
        XCTAssertEqual(try XCTUnwrap(light.otherAdvances?[0x0394]), 0.722, "its own Δ, which zh-d97c5474's Greek sets in it")
        XCTAssertEqual(try XCTUnwrap(light.boldAdvances)[0], 0.270)
        XCTAssertEqual(try XCTUnwrap(OfficeFonts.face("Nunito Sans", eastAsian: false)?.naturalHeight), 1.364)
    }

    func testCambriasGreekIsCambriasWidths() throws {
        // Caladea has no Greek: zh-d97c5474's Cambria runs of it are set
        // at Cambria's own widths, "α" 1176 of 2048 and its bold's 1268.
        let face = try XCTUnwrap(OfficeFonts.face("Cambria", eastAsian: false))
        XCTAssertEqual(try XCTUnwrap(face.otherAdvances?[0x03B1]), 0.5742, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(face.boldOtherAdvances?[0x03B1]), 0.6191, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(face.otherAdvances?[0x03A9]), 0.6792, accuracy: 0.0001)
    }

    func testPMingLiUsSpaceAndTimesSignAreItsOwnWidths() throws {
        // Word's embedded PMingLiU sets the space 0.26 em (97 prints'
        // /Widths) where the stand-in set 0.235, and "×" half an em:
        // zh-0daa510e's 12pt cell "（A）×75%＋我國籍民" is one line in Word's
        // print, "×" 5.95; ours set it 6.91 and left "民". Its symbols stay
        // an em as a square face's, its digits the stand-in's.
        for name in ["新細明體", "PMingLiU"] {
            let face = try XCTUnwrap(OfficeFonts.face(name, eastAsian: true))
            let table = try XCTUnwrap(OfficeFonts.face(name, eastAsian: false)?.advances)
            XCTAssertEqual(table.count, 95, "U+0020 to U+007E")
            XCTAssertEqual(table[0], 0.26, accuracy: 0.0005)
            XCTAssertEqual(table[Int(Character("0").asciiValue!) - 0x20], 0.47, accuracy: 0.0005)
            XCTAssertEqual(try XCTUnwrap(face.otherAdvances?[0xD7]), 0.5)
            XCTAssertEqual(try XCTUnwrap(face.otherAdvances?[0xF7]), 0.591, "\"÷\", as Word's embedded PMingLiU")
            XCTAssertTrue(face.fullWidthSymbols)
        }
    }

    func testMathPresetsDrawAsOnePiece() {
        let r = Rect.fromLTWH(0, 0, 200, 200)
        for name in ["mathEqual", "mathNotEqual", "mathMultiply", "mathDivide"] {
            let path = SlidePainter.geometryPath(ShapePreset(rawValue: name), r)
            XCTAssertFalse(path.getBounds().isEmpty, name)
            XCTAssertTrue(SlidePainter.drawablePresets.contains(name), name)
        }
        // Where the stroke crosses a bar, "not equal" is filled, not holed.
        let ne = SlidePainter.geometryPath(ShapePreset(rawValue: "mathNotEqual"), r)
        XCTAssertTrue(ne.contains(Offset(100, 100 - 200 * 0.0588 - 200 * 0.1176)), "inside the top bar on the stroke")
        XCTAssertTrue(ne.contains(Offset(100, 100)), "on the stroke between the bars")
        let x = SlidePainter.geometryPath(ShapePreset(rawValue: "mathMultiply"), r)
        XCTAssertTrue(x.contains(Offset(100, 100)), "where the arms cross")
    }

    /// Slide 6's rounded box mirrored in the file: read as such, and written
    /// back mirrored once it is edited.
    func testAMirroredShapeIsReadAndWrittenBack() throws {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        var slide = String(data: package.parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        let box = try XCTUnwrap(slide.range(of: "prst=\"roundRect\""))
        let xfrm = try XCTUnwrap(slide.range(of: "<a:xfrm>", options: .backwards, range: slide.startIndex ..< box.lowerBound))
        slide.replaceSubrange(xfrm, with: "<a:xfrm flipH=\"1\">")
        package.parts["ppt/slides/slide6.xml"] = Data(slide.utf8)
        var (state, theme, pkg) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        let i = try XCTUnwrap(state.slides[5].shapes.firstIndex { $0.kind == .geometry(.roundRect) })
        XCTAssertTrue(state.slides[5].shapes[i].flipH)
        XCTAssertFalse(state.slides[5].shapes[i].flipV)
        state.slides[5].shapes[i].fill = Color(0xFF123456)
        let out = String(data: PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
            .parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        XCTAssertTrue(out.contains("<a:xfrm flipH=\"1\">"), "the regenerated shape is still mirrored")
    }

    /// The table's style id names a style the deck defines: its first row,
    /// bands and whole-table fill, and its header text, are what is drawn —
    /// not the first accent.
    func testATableStyleFromTheDeckDecidesTheLook() throws {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let def = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><a:tblStyleLst \(ns) def=\"{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}\">"
            + "<a:tblStyle styleId=\"{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}\" styleName=\"Test\">"
            + "<a:wholeTbl><a:tcTxStyle><a:fontRef idx=\"minor\"><a:prstClr val=\"black\"/></a:fontRef><a:schemeClr val=\"dk1\"/></a:tcTxStyle>"
            + "<a:tcStyle><a:tcBdr><a:insideH><a:ln w=\"12700\"><a:solidFill><a:srgbClr val=\"00FFFF\"/></a:solidFill></a:ln></a:insideH></a:tcBdr>"
            + "<a:fill><a:solidFill><a:srgbClr val=\"0000FF\"/></a:solidFill></a:fill></a:tcStyle></a:wholeTbl>"
            + "<a:band1H><a:tcStyle><a:tcBdr/><a:fill><a:solidFill><a:srgbClr val=\"00FF00\"/></a:solidFill></a:fill></a:tcStyle></a:band1H>"
            + "<a:firstRow><a:tcTxStyle b=\"off\"><a:fontRef idx=\"minor\"><a:prstClr val=\"black\"/></a:fontRef><a:srgbClr val=\"FFFF00\"/></a:tcTxStyle>"
            + "<a:tcStyle><a:tcBdr/><a:fill><a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill></a:fill></a:tcStyle></a:firstRow>"
            + "</a:tblStyle></a:tblStyleLst>"
        package.parts["ppt/tableStyles.xml"] = Data(def.utf8)
        // Our writer spells the header's bold white look on its runs, which
        // would win over any style: strip it, so the style is what is left.
        let part = try XCTUnwrap(package.parts.keys.first { k in
            k.hasPrefix("ppt/slides/slide") && String(data: package.parts[k]!, encoding: .utf8)!.contains("<a:tbl>")
        })
        var slide = String(data: package.parts[part]!, encoding: .utf8)!
        slide = slide.replacingOccurrences(of: " b=\"1\"", with: "")
            .replacingOccurrences(of: "<a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill>", with: "")
        // (And the runs' own faces: the style's minor font is what is left.)
        slide = slide.replacingOccurrences(of: #"<a:(latin|cs) typeface="[^"]*"/>"#, with: "", options: .regularExpression)
        package.parts[part] = Data(slide.utf8)
        let (state, theme, _) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        let table = try XCTUnwrap(state.slides.flatMap(\.shapes).first { $0.kind == .table })
        let doc = try XCTUnwrap(table.text)
        let style = try XCTUnwrap(doc.tableStyles.values.first)
        XCTAssertEqual(style.headerFill, Color(0xFFFF0000))
        XCTAssertEqual(style.bandFill, Color(0xFF00FF00))
        XCTAssertEqual(style.bandAltFill, Color(0xFF0000FF), "band 2 shows the whole table's fill")
        XCTAssertEqual(style.borderColor, Color(0xFF00FFFF), "the rules too (the cells' own lines, stripped above, would win)")
        let header = try XCTUnwrap(doc.paragraphs.first?.runs.first?.style)
        XCTAssertEqual(header.color, Color(0xFFFFFF00))
        XCTAssertEqual(header.bold, false, "the style says the header is not bold")
        XCTAssertEqual(doc.paragraphs.last?.runs.first?.style.fontFamily, theme.bodyFont, "the style's fontRef: the theme's minor font")
    }
}

/// Presets from their definitions (2026-10-11): adjust values, text
/// rectangles, fill tones; a tiled picture at its own resolution.
final class PresetGeometryTests: XCTestCase {
    private let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""

    func testEveryPresetIsDefinedAndEvaluates() {
        for name in ["rect", "ellipse", "pie", "funnel", "mathNotEqual", "gear6", "cloud", "wedgeRectCallout", "star5",
                     "leftBrace", "can", "cube", "roundRect", "heart", "sun", "moon", "donut", "blockArc", "swooshArrow"] {
            XCTAssertTrue(PresetGeometry.has(name), name)
            XCTAssertNotNil(PresetGeometry.geometry(name, width: 914400, height: 914400), name)
        }
        XCTAssertFalse(PresetGeometry.has("noSuchShape"))
        XCTAssertNil(PresetGeometry.geometry("noSuchShape", width: 10, height: 10))
    }

    func testAPiesAnglesComeFromItsAdjustValues() throws {
        let xml = "<a:prstGeom prst=\"pie\" \(ns)><a:avLst><a:gd name=\"adj1\" fmla=\"val 20345271\"/><a:gd name=\"adj2\" fmla=\"val 5405194\"/></a:avLst></a:prstGeom>"
        let adj = PresetGeometry.adjustments(XNode.parse(Data(xml.utf8)))
        XCTAssertEqual(adj["adj1"], 20_345_271)
        XCTAssertEqual(adj["adj2"], 5_405_194)
        let g = try XCTUnwrap(PresetGeometry.geometry("pie", width: 4_320_000, height: 2_880_000, adjustments: adj))
        let d = try XCTUnwrap(PresetGeometry.geometry("pie", width: 4_320_000, height: 2_880_000))
        XCTAssertNotEqual(g.subpaths, d.subpaths, "the adjusted pie is not the default three-quarter one")
        guard case .arc(let b, let start, let sweep) = g.subpaths[0].commands[1] else { return XCTFail("an arc from the rim") }
        // From 339° on to 90° as seen from the centre — the angles of the
        // stretched ellipse's points, not its parameter: the arc ends at
        // the bottom of the frame, as in PowerPoint's print, the long way
        // round avoided.
        XCTAssertGreaterThan(sweep, 0)
        XCTAssertLessThan(sweep, .pi)
        let end = (b.center.dx + b.width / 2 * cos(start + sweep), b.center.dy + b.height / 2 * sin(start + sweep))
        XCTAssertEqual(end.0, 0.5, accuracy: 1e-3)
        XCTAssertEqual(end.1, 1.0, accuracy: 1e-3)
        let first = (b.center.dx + b.width / 2 * cos(start), b.center.dy + b.height / 2 * sin(start))
        let seen = atan2((first.1 - 0.5) * 2_880_000, (first.0 - 0.5) * 4_320_000) + 2 * .pi
        XCTAssertEqual(seen, 20_345_271 / 60000 * .pi / 180, accuracy: 1e-6)
        // The text sits in the box the definition names (the inscribed one).
        let box = try XCTUnwrap(g.textRect)
        XCTAssertEqual(box.left, 0.5 - cos(.pi / 4) / 2, accuracy: 1e-6)
        XCTAssertEqual(box.bottom, 0.5 + sin(.pi / 4) / 2, accuracy: 1e-6)
        XCTAssertNil(try XCTUnwrap(PresetGeometry.geometry("rect", width: 10, height: 10)).textRect, "a rect's text box is the whole")
    }

    func testAFunnelsRimIsAHoleAndACubesFacesAreToned() throws {
        let f = try XCTUnwrap(PresetGeometry.geometry("funnel", width: 3_600_000, height: 3_600_000))
        XCTAssertEqual(f.subpaths.count, 1)
        XCTAssertEqual(f.subpaths[0].commands.filter { if case .move = $0 { return true } else { return false } }.count, 2,
                       "the body and the rim's hole are two contours of one path")
        let c = try XCTUnwrap(PresetGeometry.geometry("cube", width: 914400, height: 914400))
        XCTAssertEqual(c.subpaths.map(\.tone), [0, -0.2, 0.2, 0], "the front, a darker side, a lighter top, the outline")
        XCTAssertEqual(c.subpaths.map(\.stroke), [false, false, false, true])
        XCTAssertEqual(FreeformGeometry.toned(Color(0xFF808080), -0.5), Color(0xFF404040))
        XCTAssertEqual(FreeformGeometry.toned(Color(0xFF808080), 0.5), Color(0xFFC0C0C0))
        XCTAssertEqual(FreeformGeometry.toned(Color(0x80123456), 0), Color(0x80123456))
    }

    func testAMathNotEqualsStrokeAngleIsAdjustable() throws {
        let upright = try XCTUnwrap(PresetGeometry.geometry("mathNotEqual", width: 100_000, height: 100_000,
                                                            adjustments: ["adj2": 5_400_000]))
        let slanted = try XCTUnwrap(PresetGeometry.geometry("mathNotEqual", width: 100_000, height: 100_000,
                                                            adjustments: ["adj2": 6_600_000]))
        XCTAssertNotEqual(upright.subpaths, slanted.subpaths)
    }

    func testAPicturesResolutionIsRead() {
        // A PNG: signature, IHDR, then pHYs at 3780 dots per metre (96 dpi).
        func be32(_ v: Int) -> [UInt8] { [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
            var out = be32(body.count)
            out += Array(type.utf8)
            out += body
            out += be32(0)
            return out
        }
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let ihdr = chunk("IHDR", [UInt8](repeating: 0, count: 13))
        var phys: [UInt8] = be32(3780)
        phys += be32(3780)
        phys += [1]
        let png = signature + ihdr + chunk("pHYs", phys) + chunk("IEND", [])
        XCTAssertEqual(PptxReader.imageDPI(Data(png))!, 96, accuracy: 0.1)
        XCTAssertNil(PptxReader.imageDPI(Data(signature + ihdr + chunk("IEND", []))), "no pHYs: none declared")
        // A JPEG with a JFIF segment at 150 dpi, and one at 300 dots per cm.
        let soi: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]
        let jfif: [UInt8] = [0, 1, 1, 1, 0, 150, 0, 150, 0, 0]
        var jpg = soi + Array("JFIF".utf8) + jfif
        XCTAssertEqual(PptxReader.imageDPI(Data(jpg))!, 150, accuracy: 0.1)
        jpg[13] = 2; jpg[14] = 1; jpg[15] = 44
        XCTAssertEqual(PptxReader.imageDPI(Data(jpg))!, 300 * 2.54, accuracy: 0.1)
        jpg[13] = 0
        XCTAssertNil(PptxReader.imageDPI(Data(jpg)), "unit 0 is an aspect ratio, not a resolution")
    }

    /// tdf152070: a tile 60% across and 70% down, aligned top left and
    /// moved 35 pt right and 40.5 down; `algn="t"` is the top middle.
    func testATilesScaleAlignmentAndOffsetAreRead() {
        let tile = XNode.parse(Data("<a:tile \(ns) tx=\"444500\" ty=\"514350\" sx=\"60000\" sy=\"70000\" flip=\"none\" algn=\"tl\"/>".utf8))
        var f = SlideFill()
        PptxReader.tile(tile, image: nil, into: &f)
        XCTAssertTrue(f.tiled)
        XCTAssertEqual(f.tileScale, 0.6 * 96 / 144, accuracy: 1e-9)
        XCTAssertEqual(f.tileScaleY, 0.7 * 96 / 144, accuracy: 1e-9)
        XCTAssertEqual(f.tileOffset, Offset(35, 40.5))
        XCTAssertEqual(f.tileAlign, Offset(0, 0))
        PptxReader.tile(XNode.parse(Data("<a:tile \(ns) algn=\"t\"/>".utf8)), image: nil, into: &f)
        XCTAssertEqual(f.tileAlign, Offset(0.5, 0))
        XCTAssertEqual(f.tileOffset, Offset(0, 0))
        PptxReader.tile(nil, image: nil, into: &f)
        XCTAssertEqual(f.tileScaleY, 96 / 144, accuracy: 1e-9, "a bare blip tiles at its own size")
    }
}

/// Table cells turned, margined and lined as the file has them
/// (2026-10-11, table_test2): `vert`, `marL`…`marB`, `lnL`…`lnB`.
final class TableCellTests: XCTestCase {
    private func tableSlide(_ package: PptxPackage) throws -> String {
        try XCTUnwrap(package.parts.keys.first { k in
            k.hasPrefix("ppt/slides/slide") && String(data: package.parts[k]!, encoding: .utf8)!.contains("<a:tbl>")
        })
    }

    /// The first cell turned to read upwards with its own margins and a
    /// thick red left line and no top line: read as such, and written back
    /// the same way once the table is edited.
    func testACellsDirectionMarginsAndLinesRoundTrip() throws {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let part = try tableSlide(package)
        var slide = String(data: package.parts[part]!, encoding: .utf8)!
        let first = try XCTUnwrap(slide.range(of: "<a:tcPr anchor=\"ctr\">"))
        let end = try XCTUnwrap(slide.range(of: "</a:tcPr>", range: first.upperBound ..< slide.endIndex))
        slide.replaceSubrange(first.lowerBound ..< end.upperBound,
                              with: "<a:tcPr marL=\"137160\" marT=\"91440\" vert=\"vert270\">"
                              + "<a:lnL w=\"76200\"><a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill></a:lnL>"
                              + "<a:lnT><a:noFill/></a:lnT></a:tcPr>")
        package.parts[part] = Data(slide.utf8)
        var (state, theme, pkg) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        let s = try XCTUnwrap(state.slides.firstIndex { $0.shapes.contains { $0.kind == .table } })
        let t = try XCTUnwrap(state.slides[s].shapes.firstIndex { $0.kind == .table })
        let doc = try XCTUnwrap(state.slides[s].shapes[t].text)
        let cell = try XCTUnwrap(doc.paragraphs.first?.cell)
        XCTAssertEqual(cell.textDirection, .up)
        XCTAssertEqual(cell.padding, EdgeInsets(left: 10.8, top: 7.2, right: 7.2, bottom: 3.6), "its own margins over PowerPoint's defaults")
        XCTAssertEqual(cell.borders.left, CellRef.CellLine(width: 6, color: Color(0xFFFF0000)))
        XCTAssertEqual(cell.borders.top, CellRef.CellLine.hidden, "no line where the style would draw one")
        XCTAssertNil(cell.borders.right, "the style's line")
        let other = try XCTUnwrap(doc.paragraphs.first { $0.cell?.column == 1 }?.cell)
        XCTAssertEqual(other.textDirection, .horizontal)
        XCTAssertEqual(other.padding, EdgeInsets(left: 7.2, top: 3.6, right: 7.2, bottom: 3.6))
        XCTAssertNotNil(other.borders.left, "the sample spells its lines on every cell")
        XCTAssertNotEqual(other.borders.left, CellRef.CellLine.hidden)
        let style = try XCTUnwrap(doc.tableStyles.values.first)
        XCTAssertNotEqual(style.borderColor, Color(0xFFFF0000), "one cell's line does not recolour the table's rules")
        // Edited, so the table is regenerated.
        var edited = doc
        edited.paragraphs[0].text = "Changed"
        edited.paragraphs[0].runs = [Run(length: 7, style: edited.paragraphs[0].runs[0].style)]
        state.slides[s].shapes[t].text = edited
        let written = PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg)))
        let out = String(data: written.parts[try tableSlide(written)]!, encoding: .utf8)!
        XCTAssertTrue(out.contains("Changed"), "regenerated: " + String(out[out.range(of: "<a:tbl>")!.lowerBound...].prefix(1500)))
        XCTAssertTrue(out.contains("vert=\"vert270\""))
        XCTAssertTrue(out.contains("marL=\"137160\""))
        XCTAssertTrue(out.contains("marT=\"91440\""))
        XCTAssertFalse(out.contains("marR="), "a default margin is not spelled out")
        XCTAssertTrue(out.contains("<a:lnL w=\"76200\"><a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill></a:lnL>"))
        XCTAssertTrue(out.contains("<a:lnT w=\"12700\"><a:noFill/></a:lnT>"))
    }

    /// A turned cell's lines run along the row's height and stack across
    /// the column: the row is as tall as the other cells make it, or as
    /// the turned cell's longest word when that is longer.
    func testATurnedCellWrapsAtTheRowHeight() throws {
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans, fontSize: 18)
        func layout(_ vertical: String?) -> (RichLayout, RichDocument) {
            var a = RichParagraph(text: "x")
            a.cell = CellRef(table: "t", row: 0, column: 0)
            var b = RichParagraph(text: vertical ?? "y")
            b.cell = CellRef(table: "t", row: 0, column: 1)
            b.cell?.textDirection = vertical == nil ? .horizontal : .up
            var doc = RichDocument(paragraphs: [a, b])
            doc.tableColumns["t"] = [100, 100]
            let l = RichLayout(theme: theme, paragraphCount: 2)
            l.width = 400
            l.ensureLaidOut(doc)
            return (l, doc)
        }
        let (plain, _) = layout(nil)
        let oneLine = plain.totalHeight
        // A word shorter than the row's height: the row keeps its height.
        let (short, _) = layout("ab")
        XCTAssertEqual(short.totalHeight, oneLine, accuracy: 0.5)
        // Words longer than it: the row grows to the longest word, which
        // wraps the rest onto further lines across the column.
        let (long, _) = layout("Wednesday afternoon")
        let word = TextPainter(text: TextSpan(text: "Wednesday", style: theme.textStyle(for: CharStyle(), in: RichParagraphStyle(), scale: 1)),
                               textDirection: .ltr)
        word.layout(minWidth: 0, maxWidth: .infinity)
        XCTAssertEqual(long.totalHeight, word.longestLine + long.cellPadding * 2, accuracy: 1.5, "the row is the longest word plus the margins")
        XCTAssertGreaterThan(long.totalHeight, oneLine)
        // The turned paragraph sits at the row's top in the flow.
        XCTAssertEqual(long.geometry(1).top, 0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(long.rowRect(1)).height, long.totalHeight, accuracy: 0.01)
    }

    /// The caret, the selection and a click in a turned cell follow its
    /// text: the caret is a bar across the run, the selection lies in the
    /// cell's column, and a click on the start caret finds the start (Slides' table
    /// cells, seen on screen 2026-10-31: the caret and selection were drawn
    /// as for across text, and a click always found the text's end).
    func testATurnedCellsCaretSelectionAndClickAreTurned() throws {
        _ = OfficeFonts.register()
        let theme = RichTextTheme(fontFamily: OfficeFonts.sans, fontSize: 18)
        for direction in [CellRef.CellTextDirection.up, .down] {
            var a = RichParagraph(text: "x")
            a.cell = CellRef(table: "t", row: 0, column: 0)
            var b = RichParagraph(text: "Wednesday")
            b.cell = CellRef(table: "t", row: 0, column: 1)
            b.cell?.textDirection = direction
            var doc = RichDocument(paragraphs: [a, b])
            doc.tableColumns["t"] = [100, 100]
            let l = RichLayout(theme: theme, paragraphCount: 2)
            l.width = 400
            l.ensureLaidOut(doc)
            let row = try XCTUnwrap(l.rowRect(1))
            let left = 100 * 96.0 / 72.0, right = 200 * 96.0 / 72.0
            func inCell(_ r: Rect, _ what: String) {
                XCTAssertGreaterThanOrEqual(r.left, left - 0.5, "\(what) \(r) \(direction)")
                XCTAssertLessThanOrEqual(r.right, right + 0.5, "\(what) \(r) \(direction)")
                XCTAssertGreaterThanOrEqual(r.top, row.top - 0.5, "\(what) \(r) \(direction)")
                XCTAssertLessThanOrEqual(r.bottom, row.bottom + 0.5, "\(what) \(r) \(direction)")
            }
            let start = l.caretRect(RichPosition(paragraph: 1, offset: 0), doc)
            let end = l.caretRect(RichPosition(paragraph: 1, offset: 9), doc)
            inCell(start, "caret at the start"); inCell(end, "caret at the end")
            XCTAssertGreaterThan(start.width, start.height, "a bar across the run, not along it")
            // Reading up starts at the foot of the row, reading down at its top.
            if direction == .up { XCTAssertGreaterThan(start.top, end.top) } else { XCTAssertLessThan(start.top, end.top) }
            let sel = RichSelection(anchor: RichPosition(paragraph: 1, offset: 0), focus: RichPosition(paragraph: 1, offset: 9))
            let rects = l.selectionRects(sel, doc)
            XCTAssertFalse(rects.isEmpty)
            for r in rects { inCell(r, "selection") }
            // A click on the start caret finds the start (it found the
            // text's end wherever it fell).
            let found = l.position(at: Offset(start.center.dx, start.center.dy), doc)
            XCTAssertEqual(found.paragraph, 1)
            XCTAssertEqual(found.offset, 0, "\(direction)")
        }
    }
}

/// Line spacing as a multiple of the face's natural line height
/// (2026-10-11): PowerPoint's and Word's "single" is the font's ascent,
/// descent and gap, not the size; a body shrunk to fit also carries the
/// share taken off its line spacing.
final class LineHeightTests: XCTestCase {
    func testSingleSpacingIsTheFacesNaturalHeight() {
        _ = OfficeFonts.register()
        let theme = RichTextTheme(fontFamily: "Carlito", fontSize: 18)
        var p = RichParagraph(text: "x")
        p.style.lineSpacing = 1.0
        let layout = RichLayout(theme: theme, paragraphCount: 1)
        layout.width = 400
        layout.ensureLaidOut(RichDocument(paragraphs: [p]))
        let line = layout.geometry(0).painter.height / theme.pixelsPerPoint
        XCTAssertEqual(line, 18 * 1.22, accuracy: 0.3, "Carlito (Calibri) is 1.22 of its size, as PowerPoint draws it")
        theme.lineSpacingReduction = 0.2
        let reduced = RichLayout(theme: theme, paragraphCount: 1)
        reduced.width = 400
        reduced.ensureLaidOut(RichDocument(paragraphs: [p]))
        // (The engine rounds a line to whole pixels: ±0.75 pt.)
        XCTAssertEqual(reduced.geometry(0).painter.height / theme.pixelsPerPoint, 18 * 1.22 * 0.8, accuracy: 0.75)
        // The face Arial is drawn in, not the name: only macOS has an Arial
        // to find by name; elsewhere the bare name lands on the engine's
        // fallback face (1.12), which is not what a document gets either.
        XCTAssertEqual(theme.naturalLineHeight(family: OfficeFonts.substitute("Arial"), bold: false, italic: false), 1.15, accuracy: 0.01)
    }

    func testAFittedBodysLineReductionRoundTrips() throws {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let part = "ppt/slides/slide2.xml"
        var slide = try XCTUnwrap(String(data: try XCTUnwrap(package.parts[part]), encoding: .utf8))
        let fit = try XCTUnwrap(slide.range(of: "<a:normAutofit"))
        let end = try XCTUnwrap(slide.range(of: "/>", range: fit.upperBound ..< slide.endIndex))
        slide.replaceSubrange(fit.lowerBound ..< end.upperBound, with: "<a:normAutofit fontScale=\"85000\" lnSpcReduction=\"20000\"/>")
        package.parts[part] = Data(slide.utf8)
        let (state, theme, pkg) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        let shape = try XCTUnwrap(state.slides[1].shapes.first { $0.fontScale < 1 })
        XCTAssertEqual(shape.lineReduction, 0.2, accuracy: 0.0001)
        let controller = DeckController()
        controller.load(state, theme: theme, package: pkg)
        let live = try XCTUnwrap(controller.slides[1].shapes.first { $0.fontScale < 1 })
        XCTAssertEqual(live.textTheme?.lineSpacingReduction ?? 0, 0.2, accuracy: 0.0001, "the theme carries it to the layout")
        let out = try XCTUnwrap(String(data: try XCTUnwrap(PptxPackage(try Zip.read(try PptxWriter.write(controller.snapshot(), theme: theme, package: pkg)))
            .parts[part]), encoding: .utf8))
        XCTAssertTrue(out.contains("lnSpcReduction=\"20000\""), out)
    }
}

/// A diagram shape with its own text frame keeps its preset outline
/// (2026-10-11, tdf150789): the callout headers of a drawn SmartArt used
/// to lose theirs and be dropped as "an arrow the painter cannot draw".
final class DiagramTextFrameTests: XCTestCase {
    func testAShapeWithATextFrameStillHasItsOutline() throws {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        var slide = String(data: package.parts["ppt/slides/slide6.xml"]!, encoding: .utf8)!
        let box = try XCTUnwrap(slide.range(of: "prst=\"roundRect\""))
        slide.replaceSubrange(box, with: "prst=\"upArrowCallout\"")
        // The text frame goes after the shape's properties, as a drawing part has it.
        let sppr = try XCTUnwrap(slide.range(of: "</p:spPr>", range: box.upperBound ..< slide.endIndex))
        slide.replaceSubrange(sppr, with: "</p:spPr><p:txXfrm><a:off x=\"914400\" y=\"914400\"/><a:ext cx=\"914400\" cy=\"457200\"/></p:txXfrm>")
        package.parts["ppt/slides/slide6.xml"] = Data(slide.utf8)
        let (state, _, _) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        let shape = try XCTUnwrap(state.slides[5].shapes.first { $0.kind == .geometry(ShapePreset(rawValue: "upArrowCallout")) })
        XCTAssertNotNil(shape.customPath, "the preset is evaluated whatever the text frame")
        // The text sits in the frame's box, not the definition's rectangle.
        XCTAssertEqual(shape.insets.left, 72 - shape.frame.left + 7.2, accuracy: 0.01)
        XCTAssertEqual(shape.insets.top, 72 - shape.frame.top + 3.6, accuracy: 0.01)
    }
}

/// Capitals, the file's own bullet glyphs and empty list paragraphs
/// (2026-10-11, 60810 and alterman_security).
final class RunCapsAndBulletTests: XCTestCase {
    func testCapsAndBulletGlyphsReadAndWriteBack() throws {
        let deck = SlidesSample.make()
        var package = PptxPackage(try Zip.read(try Pptx.write(deck)))
        let part = "ppt/slides/slide2.xml"
        var slide = try XCTUnwrap(String(data: try XCTUnwrap(package.parts[part]), encoding: .utf8))
        // The first bulleted paragraph: a Wingdings square and a capitals run.
        let bu = try XCTUnwrap(slide.range(of: "<a:buFont typeface=\"Arial\"/><a:buChar char=\"•\"/>"))
        slide.replaceSubrange(bu, with: "<a:buClr><a:srgbClr val=\"FF8800\"/></a:buClr><a:buSzPct val=\"70000\"/>"
                              + "<a:buFont typeface=\"Wingdings\"/><a:buChar char=\"§\"/>")
        let run = try XCTUnwrap(slide.range(of: "<a:rPr", range: bu.lowerBound ..< slide.endIndex))
        slide.replaceSubrange(run, with: "<a:rPr cap=\"all\"")
        package.parts[part] = Data(slide.utf8)
        var (state, theme, pkg) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        let s = try XCTUnwrap(state.slides[1].shapes.firstIndex { $0.text?.paragraphs.contains { $0.style.list == .bullet } == true })
        let doc = try XCTUnwrap(state.slides[1].shapes[s].text)
        let i = try XCTUnwrap(doc.paragraphs.firstIndex { $0.style.list == .bullet })
        XCTAssertEqual(doc.paragraphs[i].style.bulletText, "▪", "Wingdings' § is a small square")
        XCTAssertEqual(doc.paragraphs[i].style.bulletColor, Color(0xFFFF8800))
        XCTAssertEqual(doc.paragraphs[i].style.bulletScale ?? 0, 0.7, accuracy: 0.0001)
        XCTAssertTrue(doc.paragraphs[i].runs[0].style.caps)
        XCTAssertNotEqual(doc.paragraphs[i].text, doc.paragraphs[i].text.uppercased(), "the text keeps its case; the layout shows capitals")
        // Written back once edited.
        var edited = doc
        edited.paragraphs[i].text += "!"
        edited.paragraphs[i].runs[edited.paragraphs[i].runs.count - 1].length += 1
        state.slides[1].shapes[s].text = edited
        let out = try XCTUnwrap(String(data: try XCTUnwrap(PptxPackage(try Zip.read(try PptxWriter.write(state, theme: theme, package: pkg))).parts[part]), encoding: .utf8))
        XCTAssertTrue(out.contains("<a:buChar char=\"▪\"/>"))
        XCTAssertTrue(out.contains("<a:buClr><a:srgbClr val=\"FF8800\"/></a:buClr><a:buSzPct val=\"70000\"/>"))
        XCTAssertTrue(out.contains("cap=\"all\""))
    }

    /// Wingdings' round bullet is drawn in a face whose "●" is its size,
    /// and the file's own bullet face and size are what is kept.
    func testWingdingsRoundBulletIsDrawnAtItsOwnSize() throws {
        let part = "<a:pPr marL=\"342900\" indent=\"-342900\"><a:buSzPct val=\"80000\"/><a:buFont typeface=\"Wingdings\" pitchFamily=\"2\" charset=\"2\"/><a:buChar char=\"l\"/></a:pPr>"
        var package = PptxPackage(try Zip.read(try Pptx.write(SlidesSample.make())))
        let key = "ppt/slides/slide2.xml"
        var slide = String(data: try XCTUnwrap(package.parts[key]), encoding: .utf8)!
        let p = try XCTUnwrap(slide.range(of: "<a:p>"))
        slide.replaceSubrange(p, with: "<a:p>" + part)
        package.parts[key] = Data(slide.utf8)
        let (read, _, _) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        let para = try XCTUnwrap(read.slides[1].shapes.lazy.compactMap { $0.text?.paragraphs.first { $0.style.bulletText == "●" } }.first)
        XCTAssertEqual(para.style.bulletStandInFamily, OfficeFonts.calibri)
        XCTAssertEqual(para.style.bulletStandInScale ?? 0, 0.565 / 0.46, accuracy: 1e-9)
        XCTAssertEqual(para.style.bulletScale ?? 0, 0.8, accuracy: 1e-9, "the file's size, as written back")
    }

    /// A preset dash cuts a line into its pieces, in widths of the line.
    func testADashedLineIsCutIntoThePatternsPieces() {
        XCTAssertEqual(SlidePainter.dashPattern("dash"), [4, 3])
        XCTAssertEqual(SlidePainter.dashPattern("sysDashDotDot"), [3, 1, 1, 1, 1, 1])
        XCTAssertNil(SlidePainter.dashPattern("solid"))
        let line = Path()
        line.moveTo(0, 0)
        line.lineTo(70, 0)
        let dashed = SlidePainter.dashed(line, "dash", width: 2)
        // 8 on, 6 off over 70: five dashes.
        let pieces = Array(dashed.computeMetrics())
        XCTAssertEqual(pieces.count, 5)
        XCTAssertEqual(pieces.map(\.length).reduce(0, +), 40, accuracy: 0.01)
        XCTAssertTrue(SlidePainter.dashed(line, nil, width: 2) === line, "solid: the path itself")
    }

    /// A shape hidden itself, or by its group, is read and kept but not drawn.
    func testAHiddenShapeIsNotDrawn() throws {
        var package = PptxPackage(try Zip.read(try Pptx.write(SlidesSample.make())))
        let key = "ppt/slides/slide2.xml"
        var slide = String(data: try XCTUnwrap(package.parts[key]), encoding: .utf8)!
        let nv = try XCTUnwrap(slide.range(of: "<p:nvSpPr><p:cNvPr id=\""))
        slide.replaceSubrange(nv, with: "<p:nvSpPr><p:cNvPr hidden=\"1\" id=\"")
        package.parts[key] = Data(slide.utf8)
        let (read, _, _) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
        XCTAssertEqual(read.slides[1].shapes.filter(\.invisible).count, 1)
    }

    /// A shape's own outer shadow is read; one cast on the ground is not.
    func testAShapesShadowIsRead() throws {
        func read(_ effect: String) throws -> [ShapeState] {
            var package = PptxPackage(try Zip.read(try Pptx.write(SlidesSample.make())))
            let key = "ppt/slides/slide2.xml"
            var slide = String(data: try XCTUnwrap(package.parts[key]), encoding: .utf8)!
            let end = try XCTUnwrap(slide.range(of: "</p:spPr>"))
            slide.replaceSubrange(end, with: "<a:solidFill><a:srgbClr val=\"4472C4\"/></a:solidFill><a:effectLst>\(effect)</a:effectLst></p:spPr>")
            package.parts[key] = Data(slide.utf8)
            let (state, _, _) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
            return state.slides[1].shapes
        }
        let cast = try read("<a:outerShdw blurRad=\"50800\" dist=\"38100\" dir=\"5400000\" algn=\"t\" rotWithShape=\"0\"><a:prstClr val=\"black\"><a:alpha val=\"40000\"/></a:prstClr></a:outerShdw>")
        let sh = try XCTUnwrap(cast.lazy.compactMap(\.shadow).first)
        XCTAssertEqual(sh.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(sh.dy, 3, accuracy: 1e-9, "three points straight down")
        XCTAssertEqual(sh.blur, 4, accuracy: 1e-9)
        let ground = try read("<a:outerShdw blurRad=\"50800\" dist=\"38100\" dir=\"5400000\" sy=\"23000\" kx=\"-1200000\"><a:prstClr val=\"black\"/></a:outerShdw>")
        XCTAssertTrue(ground.allSatisfy { $0.shadow == nil })
    }

    func testAnEmptyListParagraphShowsNoMarkerInSlides() {
        func bytesDrawn(marking: Bool) -> Int {
            let theme = RichTextTheme(fontFamily: OfficeFonts.sans, fontSize: 18)
            theme.marksEmptyListItems = marking
            var p = RichParagraph(text: "")
            p.style.list = .bullet
            let layout = RichLayout(theme: theme, paragraphCount: 1)
            layout.width = 300
            let doc = RichDocument(paragraphs: [p])
            layout.ensureLaidOut(doc)
            XCTAssertNotNil(layout.listLabel(0, doc), "the label exists for the editor either way")
            let recorder = NativePictureRecorder()
            let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, 300, 100))
            layout.paint(canvas, visible: Rect.fromLTWH(0, 0, 300, 100), document: doc, selection: nil, caret: nil)
            let picture = recorder.endRecording()
            defer { picture.dispose() }
            return picture.approximateBytesUsed
        }
        XCTAssertLessThan(bytesDrawn(marking: false), bytesDrawn(marking: true), "Slides draws no marker; Writer does")
    }
}

/// An object the deck cannot draw is boxed in the editor only (2026-10-11,
/// Divino_Revelado): a show and an export show nothing, as PowerPoint does.
final class PlaceholderBoxTests: XCTestCase {
    func testAnUndrawableObjectIsBoxedOnlyInTheEditor() {
        func bytes(placeholders: Bool) -> Int {
            let object = OpaqueObject(xml: "<p:pic/>", label: "Picture", sourcePart: "ppt/slides/slide1.xml")
            let shape = SlideShape(id: 1, name: "Picture 1", kind: .opaque(object), frame: Rect.fromLTWH(100, 100, 300, 200),
                                   text: nil, textTheme: nil)
            let slide = Slide(id: 1, layout: .blank, shapes: [shape], notes: RichDocumentController())
            let painter = SlidePainter(slide: slide, theme: DeckTheme.presets[0], slideSize: Size(960, 540), revision: 0,
                                       cache: SlideTextCache(), placeholders: placeholders)
            let recorder = NativePictureRecorder()
            let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, 960, 540))
            painter.paint(canvas, Size(960, 540))
            let picture = recorder.endRecording()
            defer { picture.dispose() }
            return picture.approximateBytesUsed
        }
        XCTAssertLessThan(bytes(placeholders: false), bytes(placeholders: true), "the labelled box is the editor's")
    }
}

/// WMF and EMF pictures played into drawing steps (2026-10-11): what a
/// deck shows for clip art, an embedded object's preview or a control.
final class MetafileTests: XCTestCase {
    private func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    private func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16((v >> 16) & 0xFFFF) }

    /// A WMF record: its function and 16-bit parameters, last argument first.
    private func wmf(_ fn: Int, _ params: [Int], tail: [UInt8] = []) -> [UInt8] {
        let body = params.flatMap(le16) + tail
        return le32((6 + body.count) / 2) + le16(fn) + body
    }

    func testAWMFPlaysItsWindowBrushRectangleAndText() throws {
        // The placeable header (key, handle, box, units per inch, reserved,
        // checksum), then the nine-word header proper.
        var file: [UInt8] = [0xD7, 0xCD, 0xC6, 0x9A, 0, 0]
        for v in [0, 0, 200, 100, 96, 0, 0, 0] { file += le16(v) }
        for v in [1, 9, 0x0300, 0, 0, 0, 0, 0, 0] { file += le16(v) }
        file += wmf(0x020B, [0, 0])                       // SetWindowOrg
        file += wmf(0x020C, [100, 200])                   // SetWindowExt: 200 wide, 100 high
        file += wmf(0x02FC, [0], tail: [0x10, 0x20, 0x30, 0] + le16(0))   // a solid brush, R 0x10 G 0x20 B 0x30
        file += wmf(0x012D, [0])                          // SelectObject 0
        file += wmf(0x041B, [90, 190, 10, 10])            // Rectangle: bottom, right, top, left
        let text = Array("Hi".utf8)
        file += wmf(0x0A32, [50, 20, text.count, 0], tail: text)   // ExtTextOut at (20, 50)
        file += wmf(0x0000, [])
        XCTAssertTrue(Metafile.isMetafile(Data(file)))
        let m = try XCTUnwrap(Metafile(Data(file), id: "t"))
        XCTAssertEqual(m.bounds, Rect.fromLTWH(0, 0, 199, 99), "the window is the picture, its last unit on the edge")
        guard case .fill(let path, let color) = m.steps[0] else { return XCTFail("the rectangle's fill first: \(m.steps)") }
        XCTAssertEqual(color, Color(0xFF102030), "a COLORREF is red first")
        XCTAssertEqual(path.getBounds(), Rect.fromLTRB(10, 10, 190, 90))
        guard case .stroke = m.steps[1] else { return XCTFail("then its outline, in the default pen") }
        guard case .text(let run) = m.steps[2] else { return XCTFail("then the text") }
        XCTAssertEqual(run.text, "Hi")
        XCTAssertEqual(run.at, Offset(20, 50))
    }

    func testAnEMFPlaysThroughItsWorldTransform() throws {
        func record(_ type: Int, _ ints: [Int]) -> [UInt8] { le32(type) + le32(8 + ints.count * 4) + ints.flatMap(le32) }
        // The header: bounds 0…99, a frame of 2646 × 2646 hundredths of a
        // millimetre on a 96 dpi device (100 × 100 device units).
        var header: [UInt8] = []
        for v in [1, 108, 0, 0, 99, 99, 0, 0, 2646, 2646] { header += le32(v) }
        header += [0x20, 0x45, 0x4D, 0x46]
        for v in [0x10000, 0, 0, 0, 0, 0, 0] { header += le32(v) }
        for v in [1024, 768, 271, 203] { header += le32(v) }   // device size, then its millimetres
        header += [UInt8](repeating: 0, count: 108 - header.count)
        var file = header
        let half = Int(Float(0.5).bitPattern)
        file += record(35, [half, 0, 0, half, 0, 0])                 // SetWorldTransform: half size
        file += record(39, [1, 0, 0x00FF0000, 0])                    // CreateBrushIndirect 1: blue (COLORREF 0x00BBGGRR)
        file += record(37, [1])
        file += record(37, [Int(Int32(bitPattern: 0x8000_0008))])   // the stock null pen
        file += record(43, [20, 40, 120, 140])                       // Rectangle
        file += record(14, [0, 0, 20])
        XCTAssertTrue(Metafile.isMetafile(Data(file)))
        let m = try XCTUnwrap(Metafile(Data(file), id: "e"))
        XCTAssertEqual(m.bounds.width, 101, accuracy: 0.5, "the frame in device units, to and including its last")
        XCTAssertEqual(m.steps.count, 1, "filled, not stroked: \(m.steps)")
        guard case .fill(let path, let color) = m.steps[0] else { return XCTFail("a fill") }
        XCTAssertEqual(color, Color(0xFF0000FF))
        XCTAssertEqual(path.getBounds(), Rect.fromLTRB(10, 20, 60, 70), "through the world transform")
    }

    func testAnEMFsGlyphNumbersAreNotText() throws {
        // zh-8d72961c's page 2, an EMF: its Arabic is ExtTextOutW with
        // ETO_GLYPH_INDEX, Arial's glyph numbers, which read as UTF-16
        // drew a row of Greek and Cyrillic. Text plays; glyph numbers don't.
        func textOut(_ s: String, options: Int) -> [UInt8] {
            var units = s.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
            while units.count % 4 != 0 { units.append(0) }
            // bounds, mode, x and y scales, reference, count, string offset, options, rectangle, dx offset
            let ints = [0, 0, 99, 99, 1, 0, 0, 10, 50, s.utf16.count, 76, options, 0, 0, 0, 0, 0]
            return le32(84) + le32(76 + units.count) + ints.flatMap(le32) + units
        }
        var header: [UInt8] = []
        for v in [1, 108, 0, 0, 99, 99, 0, 0, 2646, 2646] { header += le32(v) }
        header += [0x20, 0x45, 0x4D, 0x46]
        for v in [0x10000, 0, 0, 0, 0, 0, 0] { header += le32(v) }
        for v in [1024, 768, 271, 203] { header += le32(v) }
        header += [UInt8](repeating: 0, count: 108 - header.count)
        let file = header + textOut("Arabic", options: 0x4) + textOut("\u{3DD}\u{38E}\u{3E3}", options: 0x14) + le32(14) + le32(20) + le32(0) + le32(0) + le32(20)
        let m = try XCTUnwrap(Metafile(Data(file), id: "g"))
        let texts = m.steps.compactMap { step -> String? in if case .text(let run) = step { return run.text }; return nil }
        XCTAssertEqual(texts, ["Arabic"])
    }

    func testTextInAFaceWithoutTheGlyphsFallsBack() {
        // tika-3388: an attachment icon's caption, "約翰的測試文件" in MS
        // Gothic — Word prints seven full-width ideographs; ours drew empty
        // boxes in the Latin face standing in for MS Gothic.
        _ = OfficeFonts.register()
        XCTAssertFalse(RichTextTheme.glyphFallback.isEmpty)
        let run = Metafile.TextRun(text: "約翰的測試文件", at: .zero, size: 9, face: "MS Gothic", bold: false, italic: false,
                                   underline: false, color: Color(0xFF000000), align: 24, angle: 0)
        let style = run.style(run.color, family: OfficeFonts.substitute(run.face))
        XCTAssertEqual(style.fontFamilyFallback ?? [], RichTextTheme.glyphFallback)
        let tp = TextPainter(text: TextSpan(text: run.text, style: style), textDirection: .ltr)
        tp.layout(minWidth: 0, maxWidth: .infinity)
        defer { tp.dispose() }
        XCTAssertEqual(tp.width, 63, accuracy: 1, "seven ideographs of a 9pt em")
    }

    func testSymbolFacesShowTheirGlyphs() {
        XCTAssertEqual(Metafile.symbols("n g", face: "Webdings"), "● ■")
        // Microsoft's Wingdings cmap calls F06C/F06E circle6/square6;
        // Wingdings 2 has three/five there, not the same symbol alphabet.
        XCTAssertEqual(Metafile.symbols("l\u{F06E}", face: "Wingdings"), "●■", "the private-range spelling too")
        XCTAssertEqual(Metafile.symbols("£R\u{F053}", face: "Wingdings 2"), "☐☑☒", "Wingdings 2's own box codes")
        XCTAssertEqual(Metafile.symbols("n", face: "Arial"), "n")
    }

    func testOtherPicturesAreNotMetafiles() {
        XCTAssertFalse(Metafile.isMetafile(Data([0x89, 0x50, 0x4E, 0x47] + [UInt8](repeating: 0, count: 60))))
        XCTAssertFalse(Metafile.isMetafile(Data()))
    }

    func testAPatternFillIsItsPresetTiledFromTheSlideCorner() throws {
        let f = PatternFill.fill(preset: "ltDnDiag", foreground: Color(0xFFFF0000), background: Color(0xFF00FF00))
        XCTAssertTrue(f.tiled && f.tileAnchored)
        // A quarter of the pixels are the foreground's.
        XCTAssertEqual(f.color, Color(0xFF40BF00))
        // One pattern pixel a point: 32 pt of tile.
        let image = try XCTUnwrap(f.image)
        let side = 8 * PatternFill.repeats * PatternFill.magnify
        XCTAssertEqual(Double(side) * 0.75 * f.tileScale, Double(8 * PatternFill.repeats), accuracy: 1e-9)
        // The BMP from the top left: (0, 0) and (1, 1) are on, (1, 0) off —
        // down to the right, as PowerPoint prints ltDnDiag.
        let bytes = [UInt8](image.data)
        func red(_ x: Int, _ y: Int) -> Bool {
            let at = 54 + (side - 1 - y * PatternFill.magnify) * side * 3 + x * PatternFill.magnify * 3
            return bytes[at + 2] == 0xFF && bytes[at + 1] == 0
        }
        XCTAssertTrue(red(0, 0))
        XCTAssertTrue(red(1, 1))
        XCTAssertFalse(red(1, 0))
        XCTAssertTrue(red(4, 0))
    }

    /// A TIFF (which the image codec does not read) re-wrapped as a BMP:
    /// an uncompressed 2×1 RGB strip and the same in PackBits.
    func testTiffAsBmp() throws {
        func tiff(compression: Int, strip: [UInt8]) -> [UInt8] {
            var b: [UInt8] = [0x49, 0x49, 42, 0, 8, 0, 0, 0]
            let tags: [(Int, Int, Int)] = [(256, 3, 2), (257, 3, 1), (258, 3, 8), (259, 3, compression), (262, 3, 2),
                                           (273, 4, 8 + 2 + 9 * 12 + 4), (277, 3, 3), (278, 3, 1), (279, 4, strip.count)]
            b += [UInt8(tags.count), 0]
            for (tag, type, v) in tags {
                b += [UInt8(tag & 0xFF), UInt8(tag >> 8), UInt8(type), 0, 1, 0, 0, 0]
                b += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), 0, 0]
            }
            b += [0, 0, 0, 0]
            return b + strip
        }
        let pixels: [UInt8] = [255, 0, 0, 0, 0, 255]
        for t in [tiff(compression: 1, strip: pixels), tiff(compression: 32773, strip: [5] + pixels)] {
            XCTAssertTrue(Tiff.isTiff(t))
            let bmp = try XCTUnwrap(Tiff.bmp(t))
            XCTAssertEqual(Array(bmp[0 ..< 2]), [0x42, 0x4D])
            // Top-down BGRA: red, then blue.
            XCTAssertEqual(Array(bmp[(14 + 108)...]), [0, 0, 255, 255, 255, 0, 0, 255])
        }
    }

    /// A PNG with a bad chunk CRC and a bad Adler sum (crash-57308's
    /// footer): repaired into one whose checksums hold and whose pixels
    /// are the same.
    func testDamagedPngRepaired() throws {
        let broken: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
            0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, 0x1F, 0x00, 0x05, 0x00, 0x01, 0x00, 0xA4, 0x9B,
            0x2D, 0x6F, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]
        let fixed = try XCTUnwrap(Png.repaired(broken))
        // The IDAT's payload inflates (zlib, checked) back to the one red pixel.
        let start = try XCTUnwrap((8 ..< fixed.count - 4).first { fixed[$0] == 0x49 && fixed[$0 + 1] == 0x44 && fixed[$0 + 2] == 0x41 && fixed[$0 + 3] == 0x54 })
        let n = Int(fixed[start - 4]) << 24 | Int(fixed[start - 3]) << 16 | Int(fixed[start - 2]) << 8 | Int(fixed[start - 1])
        let payload = Array(fixed[start + 4 ..< start + 4 + n])
        let raw = try Zip.inflate(Data(payload.dropFirst(2).dropLast(4)), expected: 16)
        XCTAssertEqual([UInt8](raw), [0, 0xFF, 0, 0, 0xFF])
        XCTAssertNil(Png.repaired([1, 2, 3]))
    }
}
