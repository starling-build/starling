import XCTest
import Flutter
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
        guard case .arc(_, let start, let sweep) = g.subpaths[0].commands[1] else { return XCTFail("an arc from the rim") }
        XCTAssertEqual(start, 20_345_271 / 60000 * .pi / 180, accuracy: 1e-9)
        // From 339° on to 90°: 111° of sweep, the long way round avoided.
        XCTAssertEqual(sweep, (5_405_194 - 20_345_271 + 21_600_000) / 60000 * .pi / 180, accuracy: 1e-9)
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
        XCTAssertEqual(m.bounds, Rect.fromLTWH(0, 0, 200, 100), "the window is the picture")
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
        XCTAssertEqual(m.bounds.width, 100, accuracy: 0.5, "the frame in device units")
        XCTAssertEqual(m.steps.count, 1, "filled, not stroked: \(m.steps)")
        guard case .fill(let path, let color) = m.steps[0] else { return XCTFail("a fill") }
        XCTAssertEqual(color, Color(0xFF0000FF))
        XCTAssertEqual(path.getBounds(), Rect.fromLTRB(10, 20, 60, 70), "through the world transform")
    }

    func testSymbolFacesShowTheirGlyphs() {
        XCTAssertEqual(Metafile.symbols("n g", face: "Webdings"), "● ■")
        XCTAssertEqual(Metafile.symbols("l\u{F06E}", face: "Wingdings 2"), "●■", "the private-range spelling too")
        XCTAssertEqual(Metafile.symbols("n", face: "Arial"), "n")
    }

    func testOtherPicturesAreNotMetafiles() {
        XCTAssertFalse(Metafile.isMetafile(Data([0x89, 0x50, 0x4E, 0x47] + [UInt8](repeating: 0, count: 60))))
        XCTAssertFalse(Metafile.isMetafile(Data()))
    }
}
