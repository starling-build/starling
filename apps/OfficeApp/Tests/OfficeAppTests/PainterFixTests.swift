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
        package.parts[part] = Data(slide.utf8)
        let (state, _, _) = try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
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
    }
}
