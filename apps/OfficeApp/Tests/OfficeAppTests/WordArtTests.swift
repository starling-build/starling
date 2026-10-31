import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

/// WordArt (`prstTxWarp`, a run's gradient and outline) and shapes with
/// depth (`scene3d`, `sp3d`): what is read of them, and what goes back.
final class WordArtTests: XCTestCase {
    private let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\""
    private var colors: ColorContext {
        var t = PptxTheme(nil)
        t.colors = ["dk1": Color(0xFF000000), "lt1": Color(0xFFFFFFFF), "accent1": Color(0xFF4472C4)]
        return ColorContext(theme: t)
    }

    /// The sample deck with its second slide's first body rewritten by `edit`.
    private func deck(_ edit: (inout String) throws -> Void) throws -> (DeckState, DeckTheme, PptxPackage) {
        var package = PptxPackage(try Zip.read(try Pptx.write(SlidesSample.make())))
        let part = "ppt/slides/slide2.xml"
        var slide = try XCTUnwrap(String(data: try XCTUnwrap(package.parts[part]), encoding: .utf8))
        try edit(&slide)
        package.parts[part] = Data(slide.utf8)
        return try Pptx.read(try Zip.write(package.parts.map { ZipEntry(name: $0.key, data: $0.value) }))
    }

    func testABodysWarpIsReadAndWrittenBack() throws {
        let warp = "<a:prstTxWarp prst=\"textInflate\"><a:avLst><a:gd name=\"adj\" fmla=\"val 20000\"/></a:avLst></a:prstTxWarp>"
        let (state, theme, pkg) = try deck { slide in
            let fit = try XCTUnwrap(slide.range(of: "<a:normAutofit"))
            slide.insert(contentsOf: warp, at: fit.lowerBound)
        }
        let shape = try XCTUnwrap(state.slides[1].shapes.first { $0.warp != nil })
        XCTAssertEqual(shape.warp?.preset, "textInflate")
        XCTAssertEqual(shape.warp?.adjust ?? [], [20000])
        let out = try PptxWriter.write(state, theme: theme, package: pkg)
        let again = try Pptx.read(out).0
        XCTAssertEqual(again.slides[1].shapes.first { $0.warp != nil }?.warp?.preset, "textInflate")
    }

    /// `a:fillOverlay`: a second fill blended over the shape's own (the
    /// Concourse theme's corner, a texture multiplied by a blue gradient).
    func testAFillOverlayIsReadOverTheFill() throws {
        let (state, _, _) = try deck { slide in
            let end = try XCTUnwrap(slide.range(of: "</p:spPr>"))
            slide.replaceSubrange(end, with: "<a:solidFill><a:srgbClr val=\"FFFFFF\"/></a:solidFill><a:effectLst><a:fillOverlay blend=\"mult\">"
                + "<a:solidFill><a:srgbClr val=\"2DA2BF\"/></a:solidFill></a:fillOverlay></a:effectLst></p:spPr>")
        }
        let shape = try XCTUnwrap(state.slides[1].shapes.first { $0.fillStyle?.overlay != nil })
        XCTAssertEqual(shape.fillStyle?.color, Color(0xFFFFFFFF), "the shape's own fill under it")
        XCTAssertEqual(shape.fillStyle?.overlay?.blend, "mult")
        XCTAssertEqual(shape.fillStyle?.overlay?.fill.color, Color(0xFF2DA2BF))
    }

    /// A run's outer shadow is read (three points down and right), one
    /// cast on the ground is not, and the shadow is written back.
    func testARunsShadowIsReadAndWrittenBack() throws {
        let shadow = "<a:effectLst><a:outerShdw blurRad=\"38100\" dist=\"38100\" dir=\"2700000\" algn=\"tl\"><a:srgbClr val=\"000000\"/></a:outerShdw></a:effectLst>"
        let (state, theme, pkg) = try deck { slide in
            let run = try XCTUnwrap(slide.range(of: "<a:rPr lang=\"en-US\""))
            let end = try XCTUnwrap(slide.range(of: "</a:rPr>", range: run.upperBound ..< slide.endIndex))
            slide.replaceSubrange(end, with: shadow + "</a:rPr>")
        }
        let run = try XCTUnwrap(state.slides[1].shapes.lazy.compactMap { $0.text?.paragraphs.lazy.flatMap(\.runs).first { $0.style.shadow != nil } }.first)
        let sh = try XCTUnwrap(run.style.shadow)
        XCTAssertEqual(sh.dx, 3 * cos(.pi / 4), accuracy: 1e-6)
        XCTAssertEqual(sh.dy, 3 * sin(.pi / 4), accuracy: 1e-6)
        XCTAssertEqual(sh.blur, 3, accuracy: 1e-6)
        let again = try Pptx.read(try PptxWriter.write(state, theme: theme, package: pkg)).0
        XCTAssertNotNil(again.slides[1].shapes.lazy.compactMap { $0.text?.paragraphs.lazy.flatMap(\.runs).first { $0.style.shadow != nil } }.first)
    }

    /// A run's `a:highlight` is read and written back.
    func testARunsHighlightIsReadAndWrittenBack() throws {
        let (state, theme, pkg) = try deck { slide in
            let run = try XCTUnwrap(slide.range(of: "<a:rPr lang=\"en-US\""))
            let end = try XCTUnwrap(slide.range(of: "</a:rPr>", range: run.upperBound ..< slide.endIndex))
            slide.replaceSubrange(end, with: "<a:highlight><a:srgbClr val=\"FF0000\"/></a:highlight></a:rPr>")
        }
        func lit(_ s: DeckState) -> CharStyle? {
            s.slides[1].shapes.lazy.compactMap { $0.text?.paragraphs.lazy.flatMap(\.runs).first { $0.style.highlight != nil } }.first?.style
        }
        XCTAssertEqual(lit(state)?.highlight, Color(0xFFFF0000))
        let again = try Pptx.read(try PptxWriter.write(state, theme: theme, package: pkg)).0
        XCTAssertEqual(lit(again)?.highlight, Color(0xFFFF0000))
    }

    func testNoShapeIsNoWarp() throws {
        let (state, _, _) = try deck { slide in
            let fit = try XCTUnwrap(slide.range(of: "<a:normAutofit"))
            slide.insert(contentsOf: "<a:prstTxWarp prst=\"textNoShape\"><a:avLst/></a:prstTxWarp>", at: fit.lowerBound)
        }
        XCTAssertNil(state.slides[1].shapes.first { $0.warp != nil })
    }

    func testTheBendsKeepTheirEdges() throws {
        // Inflate: its ends drawn in by the adjust, its middle the whole height.
        let inflate = try XCTUnwrap(WordArt.envelope(TextWarp(preset: "textInflate", adjust: [20000], xml: "")))
        XCTAssertEqual(inflate(0).top, 0.2, accuracy: 1e-9)
        XCTAssertEqual(inflate(0.5).top, 0, accuracy: 1e-9)
        XCTAssertEqual(inflate(0.5).bottom, 1, accuracy: 1e-9)
        // A wave is as tall everywhere, and ends where it began.
        let wave = try XCTUnwrap(WordArt.envelope(TextWarp(preset: "textWave1", adjust: [], xml: "")))
        for u in [0.0, 0.25, 0.6, 1.0] { XCTAssertEqual(wave(u).bottom - wave(u).top, 0.75, accuracy: 1e-9) }
        XCTAssertEqual(wave(0).top, wave(1).top, accuracy: 1e-9)
        // A curve tapers over a level foot; a cascade climbs from its full height.
        let curve = try XCTUnwrap(WordArt.envelope(TextWarp(preset: "textCurveDown", adjust: [50000], xml: "")))
        XCTAssertEqual(curve(0).top, 0, accuracy: 1e-9)
        XCTAssertEqual(curve(1).top, 0.5, accuracy: 1e-9)
        XCTAssertEqual(curve(0.3).bottom, 1, accuracy: 1e-9)
        // Every bend PowerPoint offers is drawn, by one of the three ways.
        for name in ["Plain", "Stop", "Triangle", "TriangleInverted", "Chevron", "ChevronInverted", "RingInside", "RingOutside",
                     "ArchUp", "ArchDown", "Circle", "Button", "ArchUpPour", "ArchDownPour", "CirclePour", "ButtonPour",
                     "CurveUp", "CurveDown", "CanUp", "CanDown", "Wave1", "Wave2", "DoubleWave1", "Wave4", "Inflate",
                     "Deflate", "InflateBottom", "DeflateBottom", "InflateTop", "DeflateTop", "DeflateInflate",
                     "DeflateInflateDeflate", "FadeRight", "FadeLeft", "FadeUp", "FadeDown", "SlantUp", "SlantDown",
                     "CascadeUp", "CascadeDown"] {
            XCTAssertTrue(WordArt.draws(TextWarp(preset: "text" + name, adjust: [], xml: "")), name)
        }
        XCTAssertFalse(WordArt.draws(TextWarp(preset: "textNoShape", adjust: [], xml: "")))
    }

    /// ECMA's downward slant and isolated Word prints at 28569, 50000,
    /// 100000: the adjustment grows the band, not the displacement.
    func testDownwardSlantBecomesRectangularAtItsMaximum() throws {
        let thin = try XCTUnwrap(WordArt.envelope(TextWarp(preset: "textSlantDown", adjust: [28569], xml: "")))
        XCTAssertEqual(thin(0).top, 0, accuracy: 1e-9)
        XCTAssertEqual(thin(0).bottom, 0.28569, accuracy: 1e-9)
        XCTAssertEqual(thin(1).top, 0.71431, accuracy: 1e-9)
        XCTAssertEqual(thin(1).bottom, 1, accuracy: 1e-9)
        let rectangle = try XCTUnwrap(WordArt.envelope(TextWarp(preset: "textSlantDown", adjust: [100000], xml: "")))
        for x in [0.0, 0.5, 1.0] {
            XCTAssertEqual(rectangle(x).top, 0, accuracy: 1e-9)
            XCTAssertEqual(rectangle(x).bottom, 1, accuracy: 1e-9)
        }
    }

    func testInkBoundsExcludeSpacesWithoutChangingLayout() throws {
        _ = OfficeFonts.register()
        func painter(_ text: String) -> TextPainter {
            let p = TextPainter(text: TextSpan(text: text, style: Flutter.TextStyle(fontSize: 40, fontFamily: OfficeFonts.sans)), textDirection: .ltr)
            p.layout(maxWidth: Double.infinity)
            return p
        }
        let letter = painter("M"), padded = painter(" M "), blank = painter("   ")
        defer { letter.dispose(); padded.dispose(); blank.dispose() }
        let ink = try XCTUnwrap(letter.getGlyphInkBounds())
        let paddedInk = try XCTUnwrap(padded.getGlyphInkBounds())
        XCTAssertGreaterThan(ink.width, 0)
        XCTAssertEqual(paddedInk.width, ink.width, accuracy: 0.001)
        XCTAssertEqual(paddedInk.height, ink.height, accuracy: 0.001)
        XCTAssertGreaterThan(paddedInk.left, ink.left)
        XCTAssertGreaterThan(padded.width, letter.width)
        XCTAssertNil(blank.getGlyphInkBounds())
    }

    func testInkBoundsScaleWithoutRasterPadding() throws {
        _ = OfficeFonts.register()
        for text in ["M", "gjpqy"] {
            var reference: Rect?
            for size in [220.0, 40.0, 44.0 / 3] {
                let painter = TextPainter(text: TextSpan(text: text, style: Flutter.TextStyle(fontSize: size, fontFamily: OfficeFonts.sans)), textDirection: .ltr)
                defer { painter.dispose() }
                painter.layout(maxWidth: Double.infinity)
                let width = painter.width
                let ink = try XCTUnwrap(painter.getGlyphInkBounds())
                XCTAssertEqual(painter.width, width, "querying ink must not change advances")
                if let reference {
                    XCTAssertEqual(ink.width / size, reference.width / 220, accuracy: 0.00001)
                    XCTAssertEqual(ink.height / size, reference.height / 220, accuracy: 0.00001)
                } else {
                    reference = ink
                }
            }
        }
    }

    func testADepthAndACameraAreRead() throws {
        func scene(_ inner: String) -> Scene3D? {
            Extrusion.read(XNode.parse(Data("<p:spPr xmlns:p=\"p\" \(ns)>\(inner)</p:spPr>".utf8)), colors: colors)
        }
        let iso = try XCTUnwrap(scene("<a:scene3d><a:camera prst=\"isometricRightUp\"/></a:scene3d><a:sp3d extrusionH=\"457200\"/>"))
        XCTAssertEqual(iso.depth, 36, accuracy: 1e-9)
        XCTAssertEqual(iso.lon, 315, accuracy: 1e-9)
        XCTAssertNil(iso.oblique)
        // The file's own rotation beats the preset's.
        let turned = try XCTUnwrap(scene("<a:scene3d><a:camera prst=\"isometricRightUp\"><a:rot lat=\"0\" lon=\"600000\" rev=\"0\"/></a:camera></a:scene3d><a:sp3d extrusionH=\"457200\"/>"))
        XCTAssertEqual(turned.lon, 10, accuracy: 1e-9)
        XCTAssertEqual(turned.lat, 0, accuracy: 1e-9)
        // An oblique camera slides the back toward the side it is named for.
        let oblique = try XCTUnwrap(scene("<a:scene3d><a:camera prst=\"obliqueTopLeft\"/></a:scene3d><a:sp3d extrusionH=\"914400\" prstMaterial=\"legacyWireframe\"/>"))
        XCTAssertLessThan(try XCTUnwrap(oblique.oblique).dx, 0)
        XCTAssertLessThan(try XCTUnwrap(oblique.oblique).dy, 0)
        XCTAssertTrue(oblique.wireframe)
        // Square on, a solid is its own front; a camera that only revolves
        // a flat shape turns it in its plane.
        XCTAssertNil(scene("<a:scene3d><a:camera prst=\"orthographicFront\"/></a:scene3d><a:sp3d extrusionH=\"457200\"/>"))
        XCTAssertEqual(scene("<a:scene3d><a:camera prst=\"orthographicFront\"><a:rot lat=\"0\" lon=\"0\" rev=\"5400000\"/></a:camera></a:scene3d>")?.isFlatTurn, true)
        XCTAssertNil(scene("<a:solidFill><a:srgbClr val=\"FF0000\"/></a:solidFill>"))
    }
}
