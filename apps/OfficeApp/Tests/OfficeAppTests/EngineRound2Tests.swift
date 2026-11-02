// The two calls of the second engine round: a fit reserve (a line breaks as if the
// paragraph were narrower and is then set across the whole width) and the glyphs'
// outlines as a path. Each proves its call does what it says AND that the default
// (reserve 0, no range asked) changes nothing.
//
// Needs an engine built with the round (starling-engine `starling`, patches/
// skia-fit-reserve.patch): the probes `StarlingTextFitReserveSupported` and
// `StarlingTextGlyphPathSupported`. Against an older engine the tests say so and skip.

import XCTest
import Flutter
import OfficeText
import FlutterSwiftBridge
@testable import OfficeApp

final class EngineRound2Tests: XCTestCase {
    private let sentence = Array(repeating: "alpha beta gamma delta epsilon zeta eta theta iota kappa", count: 6)
        .joined(separator: " ")

    private func painter(_ text: String, justify: Bool, reserve: Double, width: Double) -> TextPainter {
        _ = OfficeFonts.register()
        let tp = TextPainter(
            text: TextSpan(text: text, style: Flutter.TextStyle(color: Color(0xFF000000), fontSize: 14, fontFamily: OfficeFonts.sans)),
            textAlign: justify ? .justify : .left, textDirection: .ltr)
        tp.fitReserve = reserve
        tp.layout(minWidth: width, maxWidth: width)
        return tp
    }

    /// Each line's text range, in UTF-16 offsets.
    private func lines(_ tp: TextPainter) -> [TextRange] {
        var out: [TextRange] = []
        var at = 0
        let end = tp.plainText.utf16.count
        while at < end {
            let r = tp.getLineBoundary(TextPosition(offset: at))
            guard r.end > at else { break }
            out.append(r)
            at = r.end
        }
        return out
    }

    private func lineEnds(_ tp: TextPainter) -> [Int] { lines(tp).map { $0.end } }

    /// Right edge of the last glyph of each line but the last (a trailing space is not a glyph's ink).
    private func lineRights(_ tp: TextPainter) -> [Double] {
        let units = Array(tp.plainText.utf16)
        return lines(tp).dropLast().compactMap { r in
            // Stop before the line's trailing spaces: the engine on Linux boxes them
            // past the justified edge (a 14pt space, 3.89, beyond the width).
            var end = r.end
            while end > r.start, units[end - 1] == 0x20 { end -= 1 }
            return tp.getBoxesForSelection(TextSelection(baseOffset: r.start, extentOffset: end))
                .map { $0.right }.max()
        }
    }

    func testAReserveOfZeroChangesNothing() throws {
        let plain = painter(sentence, justify: true, reserve: 0, width: 300)
        defer { plain.dispose() }
        let again = painter(sentence, justify: true, reserve: 0, width: 300)
        defer { again.dispose() }
        XCTAssertEqual(lineEnds(plain), lineEnds(again))
        XCTAssertEqual(plain.height, again.height)
    }

    func testAReserveBreaksEarlierButJustifiesToTheFullWidth() throws {
        guard starlingEngineKnowsFitReserve() else { throw XCTSkip("engine predates the fit reserve") }
        let width = 300.0, reserve = 40.0
        let flat = painter(sentence, justify: true, reserve: 0, width: width)
        defer { flat.dispose() }
        let held = painter(sentence, justify: true, reserve: reserve, width: width)
        defer { held.dispose() }
        let flatLines = lines(flat), heldLines = lines(held)
        // Breaking as if 40pt narrower: never fewer lines, and here more.
        XCTAssertGreaterThan(heldLines.count, flatLines.count)
        // The same paragraph laid out at width - reserve breaks at the same places as the reserve does…
        let narrow = painter(sentence, justify: true, reserve: 0, width: width - reserve)
        defer { narrow.dispose() }
        XCTAssertEqual(heldLines.map { $0.end }, lineEnds(narrow),
                       "a reserve breaks where the narrower paragraph does")
        // …but the lines are stretched across the whole width, not the narrower one.
        for right in lineRights(held) { XCTAssertEqual(right, width, accuracy: 1.0) }
        for right in lineRights(narrow) { XCTAssertEqual(right, width - reserve, accuracy: 1.0) }
    }

    func testAReserveDoesNotMoveALeftAlignedLine() throws {
        guard starlingEngineKnowsFitReserve() else { throw XCTSkip("engine predates the fit reserve") }
        let held = painter(sentence, justify: false, reserve: 40, width: 300)
        defer { held.dispose() }
        let narrow = painter(sentence, justify: false, reserve: 0, width: 260)
        defer { narrow.dispose() }
        XCTAssertEqual(lineEnds(held), lineEnds(narrow))
        for right in lineRights(held) { XCTAssertLessThanOrEqual(right, 260.5) }
    }

    func testGlyphOutlinesFollowTheLayoutAndTheRange() throws {
        guard starlingEngineKnowsGlyphPath() else { throw XCTSkip("engine predates glyph outlines") }
        let tp = painter("AB C", justify: false, reserve: 0, width: 400)
        defer { tp.dispose() }
        let whole = try XCTUnwrap(tp.glyphPath())
        let ink = try XCTUnwrap(tp.getGlyphInkBounds())
        let bounds = whole.getBounds()
        // The outlines' bounds are the ink bounds the engine already reports.
        XCTAssertEqual(bounds.left, ink.left, accuracy: 0.5)
        XCTAssertEqual(bounds.right, ink.right, accuracy: 0.5)
        XCTAssertEqual(bounds.top, ink.top, accuracy: 0.5)
        XCTAssertEqual(bounds.bottom, ink.bottom, accuracy: 0.5)
        // A range is just those glyphs: "A" lies left of "B", which lies left of "C".
        let a = try XCTUnwrap(tp.glyphPath(range: 0 ..< 1)).getBounds()
        let b = try XCTUnwrap(tp.glyphPath(range: 1 ..< 2)).getBounds()
        let c = try XCTUnwrap(tp.glyphPath(range: 3 ..< 4)).getBounds()
        XCTAssertLessThan(a.right, b.right)
        XCTAssertLessThan(b.right, c.right)
        XCTAssertEqual(a.left, bounds.left, accuracy: 0.5)
        XCTAssertEqual(c.right, bounds.right, accuracy: 0.5)
        // A space has no outline; an empty or reversed range, none either.
        XCTAssertNil(tp.glyphPath(range: 2 ..< 3))
        XCTAssertNil(tp.glyphPath(range: 1 ..< 1))
        // Past the end clamps to the text.
        XCTAssertEqual(try XCTUnwrap(tp.glyphPath(range: 0 ..< 99)).getBounds().right, bounds.right, accuracy: 0.01)
    }

    func testGlyphOutlinesOfWideTextCountUTF16Offsets() throws {
        guard starlingEngineKnowsGlyphPath() else { throw XCTSkip("engine predates glyph outlines") }
        // "é" is two bytes in UTF-8 and one UTF-16 unit; an astral letter is four and two.
        let tp = painter("aéb\u{1D41A}c", justify: false, reserve: 0, width: 400)
        defer { tp.dispose() }
        let c = try XCTUnwrap(tp.glyphPath(range: 5 ..< 6))   // "c" is the sixth unit (a é b 𝐚=2 c)
        let b = try XCTUnwrap(tp.glyphPath(range: 2 ..< 3))
        XCTAssertGreaterThan(c.getBounds().left, b.getBounds().left)
    }
}
