// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/// Property tests for the synthesized box/block glyphs.
///
/// Nothing here rasterises. `TerminalBoxGlyphs.plan` returns the geometry as
/// numbers, and these tests assert the laws that make a terminal grid look
/// continuous, at several cell geometries including fractional ones:
///
///  1. THE DECISION LIST — the set of synthesized codepoints is written out
///     here, reviewed, and `handles()` must match it exactly. A codepoint
///     falling to the font is a decision, never an accident.
///  2. EDGE CONTACT — every glyph touches exactly the cell edges its arms
///     claim. A `│` that stops one pixel short of the cell edge is the
///     per-cell-dashes bug, caught as arithmetic.
///  3. THE SEAM LAW — ink touching an edge occupies the same cross-axis band
///     as the canonical bar of its weight, so any two glyphs that should
///     connect across a cell boundary do, by equality of numbers.
///  4. BLOCKS — exact fill fractions; quadrants share midpoints.
///  5. CORNERS — the stroked path is continuous (each segment starts where
///     the previous ended), lands on its claimed edges, and its straight
///     runs sit on the canonical light bands.

import XCTest
@testable import Flutter
@testable import FlutterSwiftBridge

final class TerminalBoxGlyphsTests: XCTestCase {

    /// Cell geometries to sweep: integer, fractional-height (the shipped
    /// Linux cell), fractional-scale, 1x, and a width-refit fractional cell.
    /// Off-origin so absolute/relative confusion cannot pass.
    private static let cells: [(w: Double, h: Double, scale: Double)] = [
        (8.0, 16.0, 2.0),
        (8.0, 17.0 + 1.0 / 3.0, 2.0),
        (7.2, 15.6, 1.5),
        (9.0, 19.0, 1.0),
        (6.5, 13.65, 2.0),
    ]
    private static let ox = 3.25, oy = 7.5

    private struct Cell { let x, y, w, h, scale: Double }

    private func sweep(_ body: (Cell) -> Void) {
        for g in Self.cells {
            body(Cell(x: Self.ox, y: Self.oy, w: g.w, h: g.h, scale: g.scale))
        }
    }

    private func plan(_ scalar: UInt32, _ c: Cell) -> [BoxPlanOp] {
        TerminalBoxGlyphs.plan(scalar: scalar, x: c.x, y: c.y,
                               w: c.w, h: c.h, scale: c.scale)
    }

    private func fills(_ plan: [BoxPlanOp]) -> [Rect] {
        plan.compactMap {
            switch $0 {
            case .fill(let r): return r
            case .shade(let r, _): return r
            case .stroke: return nil
            }
        }
    }

    // The canonical bands: where a bar of a given weight sits across its
    // axis. Every glyph edge-touching ink must land on one of these.
    private func vband(_ weight: Int, _ c: Cell) -> ClosedRange<Double> {
        let t = TerminalBoxGlyphs.thickness(weight, c.scale)
        let bx = c.x + TerminalBoxGlyphs.snap((c.w - t) / 2, c.scale)
        return bx...(bx + t)
    }
    private func hband(_ weight: Int, _ c: Cell) -> ClosedRange<Double> {
        let t = TerminalBoxGlyphs.thickness(weight, c.scale)
        let by = c.y + TerminalBoxGlyphs.snap((c.h - t) / 2, c.scale)
        return by...(by + t)
    }
    private func doubleVBands(_ c: Cell) -> [ClosedRange<Double>] {
        let t = TerminalBoxGlyphs.thickness(1, c.scale)
        let bx = vband(1, c).lowerBound + t / 2      // the pair's centreline
        return [(bx - t - t / 2)...(bx - t + t / 2),
                (bx + t - t / 2)...(bx + t + t / 2)]
    }
    private func doubleHBands(_ c: Cell) -> [ClosedRange<Double>] {
        let t = TerminalBoxGlyphs.thickness(1, c.scale)
        let by = hband(1, c).lowerBound + t / 2
        return [(by - t - t / 2)...(by - t + t / 2),
                (by + t - t / 2)...(by + t + t / 2)]
    }

    private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
    private func near(_ a: ClosedRange<Double>, _ b: ClosedRange<Double>) -> Bool {
        near(a.lowerBound, b.lowerBound) && near(a.upperBound, b.upperBound)
    }

    // MARK: - 1 · The decision list

    /// Every codepoint we synthesize, written out for review. `handles()`
    /// drifting from this list — either way — is a failure.
    private static let synthesized: Set<UInt32> = {
        var s = Set<UInt32>()
        s.formUnion([0x2500, 0x2501, 0x2502, 0x2503])              // ─━│┃
        s.formUnion([0x250C, 0x250F, 0x2510, 0x2513,               // corners
                     0x2514, 0x2517, 0x2518, 0x251B])
        s.formUnion([0x251C, 0x2523, 0x2524, 0x252B,               // tees
                     0x252C, 0x2533, 0x2534, 0x253B])
        s.formUnion([0x253C, 0x254B])                              // crosses
        s.formUnion([0x2550, 0x2551, 0x2554, 0x2557, 0x255A,       // doubles
                     0x255D, 0x2560, 0x2563, 0x2566, 0x2569, 0x256C])
        s.formUnion([0x256D, 0x256E, 0x256F, 0x2570])              // rounded
        s.formUnion(0x2574...0x257F)                               // half-lines
        s.formUnion(0x2580...0x259F)                               // blocks
        return s
    }()

    func testHandlesMatchesTheDecisionList() {
        for cp in UInt32(0x2400)...UInt32(0x2A00) {
            XCTAssertEqual(TerminalBoxGlyphs.handles(cp),
                           Self.synthesized.contains(cp),
                           String(format: "U+%04X", cp))
        }
    }

    /// Every synthesized codepoint must produce a non-empty plan — a scalar
    /// that `handles()` accepts but `plan()` ignores would paint nothing.
    func testEveryHandledScalarHasAPlan() {
        sweep { c in
            for cp in Self.synthesized {
                XCTAssertFalse(plan(cp, c).isEmpty, String(format: "U+%04X", cp))
            }
        }
    }

    // MARK: - 2 · Edge contact

    private struct Claims { let up, down, left, right: Bool }

    private func armClaims(_ cp: UInt32) -> Claims? {
        guard let a = TerminalBoxGlyphs.arms(for: cp) else { return nil }
        return Claims(up: a.up > 0, down: a.down > 0,
                      left: a.left > 0, right: a.right > 0)
    }

    private static let doubleClaims: [UInt32: (up: Bool, down: Bool, left: Bool, right: Bool)] = [
        0x2550: (false, false, true, true),   // ═
        0x2551: (true, true, false, false),   // ║
        0x2554: (false, true, false, true),   // ╔
        0x2557: (false, true, true, false),   // ╗
        0x255A: (true, false, false, true),   // ╚
        0x255D: (true, false, true, false),   // ╝
        0x2560: (true, true, false, true),    // ╠
        0x2563: (true, true, true, false),    // ╣
        0x2566: (false, true, true, true),    // ╦
        0x2569: (true, false, true, true),    // ╩
        0x256C: (true, true, true, true),     // ╬
    ]

    func testArmsAndDoublesTouchExactlyTheirClaimedEdges() {
        sweep { c in
            var cases: [(UInt32, Claims)] = []
            for cp in Self.synthesized {
                if let claims = armClaims(cp) { cases.append((cp, claims)) }
                if let d = Self.doubleClaims[cp] {
                    cases.append((cp, Claims(up: d.up, down: d.down,
                                             left: d.left, right: d.right)))
                }
            }
            for (cp, claims) in cases {
                let rs = fills(plan(cp, c))
                let name = String(format: "U+%04X", cp)
                let minX = rs.map(\.left).min()!, maxX = rs.map(\.right).max()!
                let minY = rs.map(\.top).min()!, maxY = rs.map(\.bottom).max()!
                XCTAssertEqual(near(minY, c.y), claims.up, "\(name) top edge")
                XCTAssertEqual(near(maxY, c.y + c.h), claims.down, "\(name) bottom edge")
                XCTAssertEqual(near(minX, c.x), claims.left, "\(name) left edge")
                XCTAssertEqual(near(maxX, c.x + c.w), claims.right, "\(name) right edge")
            }
        }
    }

    // MARK: - 3 · The seam law

    /// Ink that touches an edge must sit exactly on the canonical band for
    /// its weight — that equality is what makes a `│` above, a `╽` below,
    /// and a `╭` beside all connect with no per-cell nick.
    func testEdgeInkSitsOnCanonicalBands() {
        sweep { c in
            for cp in Self.synthesized {
                guard let a = TerminalBoxGlyphs.arms(for: cp) else { continue }
                let name = String(format: "U+%04X", cp)
                for r in fills(plan(cp, c)) {
                    if near(r.top, c.y) {
                        XCTAssertTrue(near(r.left...r.right, vband(a.up, c)),
                                      "\(name) up band")
                    }
                    if near(r.bottom, c.y + c.h) {
                        XCTAssertTrue(near(r.left...r.right, vband(a.down, c)),
                                      "\(name) down band")
                    }
                    if near(r.left, c.x) {
                        XCTAssertTrue(near(r.top...r.bottom, hband(a.left, c)),
                                      "\(name) left band")
                    }
                    if near(r.right, c.x + c.w) {
                        XCTAssertTrue(near(r.top...r.bottom, hband(a.right, c)),
                                      "\(name) right band")
                    }
                }
            }
        }
    }

    /// Doubles: every edge-touching bar lands on one of ║/═'s two bands, so
    /// a ╔ continues into the ║ below it and the ═ beside it.
    func testDoubleEdgeInkSitsOnTheDoubleBands() {
        sweep { c in
            let vb = doubleVBands(c), hb = doubleHBands(c)
            for (cp, _) in Self.doubleClaims {
                let name = String(format: "U+%04X", cp)
                for r in fills(plan(cp, c)) {
                    let xr = r.left...r.right, yr = r.top...r.bottom
                    if near(r.top, c.y) || near(r.bottom, c.y + c.h) {
                        XCTAssertTrue(vb.contains { near(xr, $0) },
                                      "\(name) vertical band \(xr)")
                    }
                    if near(r.left, c.x) || near(r.right, c.x + c.w) {
                        XCTAssertTrue(hb.contains { near(yr, $0) },
                                      "\(name) horizontal band \(yr)")
                    }
                }
            }
        }
    }

    // MARK: - 4 · Blocks

    func testBlockFillFractions() {
        // Expected coverage as fractions of the cell, written independently
        // of the implementation. Shades carry their ink fraction.
        typealias F = (Double, Double, Double, Double)
        var expect: [UInt32: [F]] = [
            0x2580: [(0, 0, 1, 0.5)], 0x2584: [(0, 0.5, 1, 1)],
            0x2588: [(0, 0, 1, 1)],
            0x258C: [(0, 0, 0.5, 1)], 0x2590: [(0.5, 0, 1, 1)],
            0x2594: [(0, 0, 1, 1.0 / 8)], 0x2595: [(7.0 / 8, 0, 1, 1)],
        ]
        for n in 1...7 where n != 4 {                    // lower eighths ▁…▇
            expect[UInt32(0x2580 + n)] = [(0, 1 - Double(n) / 8, 1, 1)]
        }
        for n in 1...7 where n != 4 {                    // left eighths ▏…▉
            expect[UInt32(0x2590 - n)] = [(0, 0, Double(n) / 8, 1)]
        }
        let quads: [UInt32: [Int]] = [                   // UL=0 UR=1 LL=2 LR=3
            0x2596: [2], 0x2597: [3], 0x2598: [0], 0x2599: [0, 2, 3],
            0x259A: [0, 3], 0x259B: [0, 1, 2], 0x259C: [0, 1, 3],
            0x259D: [1], 0x259E: [1, 2], 0x259F: [1, 2, 3],
        ]
        let quadRect: [F] = [(0, 0, 0.5, 0.5), (0.5, 0, 1, 0.5),
                             (0, 0.5, 0.5, 1), (0.5, 0.5, 1, 1)]
        for (cp, qs) in quads { expect[cp] = qs.map { quadRect[$0] } }

        sweep { c in
            for (cp, frs) in expect {
                let name = String(format: "U+%04X", cp)
                let rs = fills(plan(cp, c))
                XCTAssertEqual(rs.count, frs.count, name)
                for f in frs {
                    XCTAssertTrue(rs.contains { r in
                        near(r.left, c.x + f.0 * c.w) && near(r.top, c.y + f.1 * c.h)
                            && near(r.right, c.x + f.2 * c.w)
                            && near(r.bottom, c.y + f.3 * c.h)
                    }, "\(name) rect \(f)")
                }
            }
            for (cp, frac) in [(UInt32(0x2591), 0.25), (0x2592, 0.5), (0x2593, 0.75)] {
                guard case .shade(let r, let f)? = plan(cp, c).first else {
                    return XCTFail(String(format: "U+%04X not a shade", cp))
                }
                XCTAssertEqual(f, frac)
                XCTAssertTrue(near(r.left, c.x) && near(r.right, c.x + c.w))
            }
        }
    }

    // MARK: - 5 · Corners

    /// The stroked corner is continuous, lands on its claimed edges, and its
    /// straight runs ride the canonical light bands.
    func testRoundedCornerContinuityAndSeams() {
        let claims: [UInt32: (vertical: String, horizontal: String)] = [
            0x256D: ("bottom", "right"), 0x256E: ("bottom", "left"),
            0x256F: ("top", "left"), 0x2570: ("top", "right"),
        ]
        sweep { c in
            let lightV = vband(1, c), lightH = hband(1, c)
            let vc = (lightV.lowerBound + lightV.upperBound) / 2
            let hc = (lightH.lowerBound + lightH.upperBound) / 2
            for (cp, claim) in claims {
                let name = String(format: "U+%04X", cp)
                guard case .stroke(let from, let segments, let t)? = plan(cp, c).first else {
                    return XCTFail("\(name) is not a stroke")
                }
                XCTAssertTrue(near(t, TerminalBoxGlyphs.thickness(1, c.scale)), name)

                // The vertical run starts on the claimed horizontal edge, on
                // the light bar's centreline.
                XCTAssertTrue(near(from.dx, vc), "\(name) vertical centreline")
                XCTAssertTrue(near(from.dy, claim.vertical == "top" ? c.y : c.y + c.h),
                              "\(name) vertical edge")

                // Walk the segments: each must begin where the previous ended.
                var at = from
                for segment in segments {
                    switch segment {
                    case .line(let to):
                        at = to
                    case .arc(let oval, let start, let sweepAngle):
                        let cx = (oval.left + oval.right) / 2
                        let cy = (oval.top + oval.bottom) / 2
                        let rx = (oval.right - oval.left) / 2
                        let ry = (oval.bottom - oval.top) / 2
                        let s = Offset(cx + rx * cos(start), cy + ry * sin(start))
                        XCTAssertTrue(near(s.dx, at.dx) && near(s.dy, at.dy),
                                      "\(name) arc start \(s) from \(at)")
                        at = Offset(cx + rx * cos(start + sweepAngle),
                                    cy + ry * sin(start + sweepAngle))
                    }
                }

                // The horizontal run ends on the claimed vertical edge, on
                // the light bar's centreline.
                XCTAssertTrue(near(at.dy, hc), "\(name) horizontal centreline")
                XCTAssertTrue(near(at.dx, claim.horizontal == "left" ? c.x : c.x + c.w),
                              "\(name) horizontal edge")
            }
        }
    }
}
