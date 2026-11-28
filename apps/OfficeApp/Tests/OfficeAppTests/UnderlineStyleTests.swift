// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
import Flutter
import FlutterSwiftBridge
@testable import OfficeText
@testable import OfficeApp

/// Word's underline kinds (`w:u w:val`, `w:color`) drawn at Word's sizes (lab ulkinds, Aptos 12 pt: a single rule 0.24 pt,
/// double 0.12 + 0.12 with 0.96 between, dash 3.96 / 1.92, dot-dot-dash 2.16 then 0.72 steps, wave 0.48 peak to peak);
/// a struck run keeps its kind; Slides' `u` names map to Word's; and Normal's own look survives a save.
final class UnderlineStyleTests: XCTestCase {
    private func theme() -> RichTextTheme {
        let t = RichTextTheme(fontFamily: OfficeFonts.sans)
        t.wordRules = true
        return t
    }

    private func styled(_ kind: String?, color: String? = nil) -> CharStyle {
        var s = CharStyle()
        s.underline = true
        s.underlineKind = kind
        s.underlineColor = color
        return s
    }

    private func rules(_ kind: String?, width: Double = 30) -> RuleSpyCanvas {
        let c = RuleSpyCanvas()
        let p = Paint(); p.color = Color(0xFF000000)
        RichLayout._paintUnderline(kind, c, p, left: 0, right: width, top: 0.6, size: 12)
        return c
    }

    func testPlainUnderlineStaysTheEnginesAndKindsAreDrawnHere() {
        let t = theme()
        XCTAssertEqual(t.textStyle(for: styled(nil), in: RichParagraphStyle(), scale: 1).decoration, TextDecoration.underline)
        XCTAssertEqual(t.textStyle(for: styled("single"), in: RichParagraphStyle(), scale: 1).decoration, TextDecoration.underline)
        for kind in ["double", "words", "wave", "dotDash"] {
            XCTAssertEqual(t.textStyle(for: styled(kind), in: RichParagraphStyle(), scale: 1).decoration, TextDecoration.none, kind)
        }
        XCTAssertEqual(t.textStyle(for: styled(nil, color: "FF0000"), in: RichParagraphStyle(), scale: 1).decoration, TextDecoration.none,
                       "a coloured rule is drawn here")
    }

    func testStruckRunKeepsItsKind() {
        var s = styled("double", color: "FF0000")
        s.strikethrough = true
        XCTAssertEqual(theme().textStyle(for: s, in: RichParagraphStyle(), scale: 1).decoration, TextDecoration.lineThrough)
        XCTAssertNotNil(RichTextTheme.ownUnderline(s, named: nil))
    }

    func testWordSizes() {
        let single = rules(nil).rects
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(single[0].top, 0.60, accuracy: 0.001); XCTAssertEqual(single[0].height, 0.24, accuracy: 0.001)
        let double = rules("double").rects
        XCTAssertEqual(double.map { $0.top }, [0.36, 1.44].map { $0 }, accuracy: 0.001)
        XCTAssertEqual(double[0].height, 0.12, accuracy: 0.001)
        let thick = rules("thick").rects
        XCTAssertEqual(thick[0].top, 0.36, accuracy: 0.001); XCTAssertEqual(thick[0].bottom, 1.44, accuracy: 0.001)
        let dash = rules("dash").rects
        XCTAssertEqual(dash[0].width, 3.96, accuracy: 0.001); XCTAssertEqual(dash[1].left - dash[0].right, 1.92, accuracy: 0.001)
        let long = rules("dashLong").rects
        XCTAssertEqual(long[0].width, 7.92, accuracy: 0.001); XCTAssertEqual(long[1].left - long[0].right, 3.96, accuracy: 0.001)
        let dots = rules("dotted").rects
        XCTAssertEqual(dots[0].width, 1.44, accuracy: 0.001); XCTAssertEqual(dots[1].left - dots[0].right, 1.44, accuracy: 0.001)
        let dd = rules("dotDotDash").rects
        XCTAssertEqual(dd.prefix(3).map { $0.width }, [2.16, 0.72, 0.72], accuracy: 0.001)
        XCTAssertEqual(dd[1].left - dd[0].right, 0.72, accuracy: 0.001)
        XCTAssertEqual(dd[3].left, 5.76, accuracy: 0.001, "period 5.76")
        let dotDash = rules("dotDash").rects
        XCTAssertEqual(dotDash[0].width, 3.0, accuracy: 0.001); XCTAssertEqual(dotDash[1].width, 0.96, accuracy: 0.001)
        XCTAssertEqual(dotDash[2].left, 5.88, accuracy: 0.001, "period 5.88")
        XCTAssertEqual(rules("dottedHeavy").rects[0].height, 1.08, accuracy: 0.001)
        XCTAssertLessThanOrEqual(rules("dash", width: 5).rects.last!.right, 5, "cut at the segment's end")
        let wave = rules("wave")
        XCTAssertEqual(wave.strokes, [0.24], accuracy: 0.001); XCTAssertTrue(wave.rects.isEmpty)
        XCTAssertEqual(rules("wavyHeavy").strokes, [0.96], accuracy: 0.001)
        XCTAssertEqual(rules("wavyDouble").strokes.count, 2)
    }

    func testSlidesNamesMapToWords() {
        let cases: [(String?, String?)] = [(nil, nil), ("none", nil), ("sng", nil), ("dbl", "double"), ("heavy", "thick"),
                                           ("wavy", "wave"), ("wavyDbl", "wavyDouble"), ("dashHeavy", "dashedHeavy"),
                                           ("dotDotDashHeavy", "dashDotDotHeavy"), ("words", "words"), ("dotDash", "dotDash")]
        for (u, kind) in cases { XCTAssertEqual(RichTextTheme.drawingMLUnderline(u), kind, u ?? "nil") }
    }

    func testRuleColourIsItsOwn() {
        XCTAssertEqual(RichTextTheme.ruleColor("FF0000"), Color(0xFFFF0000))
        XCTAssertNil(RichTextTheme.ruleColor("auto"))
        XCTAssertNil(RichTextTheme.ownUnderline(styled(nil, color: "auto"), named: nil), "auto is the plain line")
    }

    /// Open, save, reopen: Normal keeps its own underline, alignment, indents and next style.
    func testNormalSurvivesASave() throws {
        var doc = RichDocument()
        var normal = doc.styles[RichNamedStyle.normalId] ?? RichNamedStyle(id: RichNamedStyle.normalId, name: "Normal")
        var ch = normal.char
        ch.underline = true; ch.underlineKind = "double"
        normal.char = ch
        var pa = normal.paragraph
        pa.alignment = .center; pa.indentLeft = 36; pa.firstLineIndent = -18
        normal.paragraph = pa
        normal.next = "Heading1"
        doc.styles[RichNamedStyle.normalId] = normal
        var back = try DocxFormat.read(DocxFormat.write(doc, pageSetup: .letter)).document
        let n = try XCTUnwrap(back.styles[RichNamedStyle.normalId])
        XCTAssertTrue(n.char.underline); XCTAssertEqual(n.char.underlineKind, "double")
        XCTAssertEqual(n.paragraph.alignment, .center)
        XCTAssertEqual(n.paragraph.indentLeft, 36); XCTAssertEqual(n.paragraph.firstLineIndent, -18)
        XCTAssertEqual(n.next, "Heading1")
        // And saved again from the file it now is, after a change to Normal.
        var again = n
        again.paragraph.alignment = .right
        back.styles[RichNamedStyle.normalId] = again
        let third = try DocxFormat.read(DocxFormat.write(back, pageSetup: .letter)).document
        let m = try XCTUnwrap(third.styles[RichNamedStyle.normalId])
        XCTAssertEqual(m.paragraph.alignment, .right)
        XCTAssertEqual(m.char.underlineKind, "double", "a changed Normal keeps the rest of its look")
        XCTAssertEqual(m.paragraph.indentLeft, 36)
    }
}

private func XCTAssertEqual(_ a: [Double], _ b: [Double], accuracy: Double, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, message, file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, message, file: file, line: line) }
}

/// Records filled rectangles and stroked paths.
private final class RuleSpyCanvas: Canvas {
    var rects: [Rect] = []
    var strokes: [Double] = []
    func save() {}
    func saveLayer(_ bounds: Rect?, _ paint: Paint) {}
    func restore() {}
    func restoreToCount(_ count: Int) {}
    func getSaveCount() -> Int { 1 }
    func translate(_ dx: Double, _ dy: Double) {}
    func scale(_ sx: Double, _ sy: Double?) {}
    func rotate(_ radians: Double) {}
    func skew(_ sx: Double, _ sy: Double) {}
    func transform(_ matrix4: [Double]) {}
    func getTransform() -> [Double] { [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1] }
    func clipRect(_ rect: Rect, clipOp: ClipOp, doAntiAlias: Bool) {}
    func clipRRect(_ rrect: RRect, doAntiAlias: Bool) {}
    func clipRSuperellipse(_ rsuperellipse: RSuperellipse, doAntiAlias: Bool) {}
    func clipPath(_ path: Path, doAntiAlias: Bool) {}
    func getLocalClipBounds() -> Rect { Rect.fromLTWH(-1e6, -1e6, 2e6, 2e6) }
    func getDestinationClipBounds() -> Rect { Rect.fromLTWH(-1e6, -1e6, 2e6, 2e6) }
    func drawColor(_ color: Color, _ blendMode: BlendMode) {}
    func drawLine(_ p1: Offset, _ p2: Offset, _ paint: Paint) {}
    func drawPaint(_ paint: Paint) {}
    func drawRect(_ rect: Rect, _ paint: Paint) { rects.append(rect) }
    func drawRRect(_ rrect: RRect, _ paint: Paint) {}
    func drawDRRect(_ outer: RRect, _ inner: RRect, _ paint: Paint) {}
    func drawRSuperellipse(_ rsuperellipse: RSuperellipse, _ paint: Paint) {}
    func drawOval(_ rect: Rect, _ paint: Paint) {}
    func drawCircle(_ c: Offset, _ radius: Double, _ paint: Paint) {}
    func drawArc(_ rect: Rect, _ startAngle: Double, _ sweepAngle: Double, _ useCenter: Bool, _ paint: Paint) {}
    func drawPath(_ path: Path, _ paint: Paint) { strokes.append(paint.strokeWidth) }
    func drawImage(_ image: Image, _ offset: Offset, _ paint: Paint) {}
    func drawImageRect(_ image: Image, _ src: Rect, _ dst: Rect, _ paint: Paint) {}
    func drawImageNine(_ image: Image, _ center: Rect, _ dst: Rect, _ paint: Paint) {}
    func drawPicture(_ picture: any FlutterSwiftBridge.Picture) {}
    func drawParagraph(_ paragraph: any Paragraph, _ offset: Offset) {}
    func drawPoints(_ pointMode: PointMode, _ points: [Offset], _ paint: Paint) {}
    func drawRawPoints(_ pointMode: PointMode, _ points: [Float], _ paint: Paint) {}
    func drawVertices(_ vertices: Vertices, _ blendMode: BlendMode, _ paint: Paint) {}
    func drawAtlas(_ atlas: Image, _ transforms: [RSTransform], _ rects: [Rect], _ colors: [Color]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawRawAtlas(_ atlas: Image, _ rstTransforms: [Float], _ rects: [Float], _ colors: [Int32]?, _ blendMode: BlendMode?, _ cullRect: Rect?, _ paint: Paint) {}
    func drawShadow(_ path: Path, _ color: Color, _ elevation: Double, _ transparentOccluder: Bool) {}
}
