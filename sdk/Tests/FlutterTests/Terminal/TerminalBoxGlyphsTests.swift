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
            case .stroke, .disc, .fillPath: return nil
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
        // The COMPLETE box-drawing block: lines and dashes, all 64
        // corner/tee/cross variants including the mixed weights, the double
        // set pure and hybrid, rounded corners, diagonals, half-lines —
        // and the complete block-elements block.
        s.formUnion(0x2500...0x259F)
        s.formUnion(0x2800...0x28FF)                               // braille
        s.formUnion(0x1FB00...0x1FB8F)                 // sextants, wedges, eighths
        s.formUnion(0x1CD00...0x1CDE5)                             // octants
        s.formUnion(0xE0B0...0xE0B7)                               // powerline
        return s
    }()

    func testHandlesMatchesTheDecisionList() {
        let sweeps: [ClosedRange<UInt32>] = [0x2400...0x2A00, 0xE0A0...0xE0D8,
                                             0x1FA00...0x1FC00, 0x1CC00...0x1CF00]
        for range in sweeps {
            for cp in range {
                XCTAssertEqual(TerminalBoxGlyphs.handles(cp),
                               Self.synthesized.contains(cp),
                               String(format: "U+%04X", cp))
            }
        }
    }

    /// Every synthesized codepoint must produce a non-empty plan — a scalar
    /// that `handles()` accepts but `plan()` ignores would paint nothing.
    /// (U+2800, the empty braille pattern, correctly paints nothing.)
    func testEveryHandledScalarHasAPlan() {
        sweep { c in
            for cp in Self.synthesized where cp != 0x2800 {
                XCTAssertFalse(plan(cp, c).isEmpty, String(format: "U+%04X", cp))
            }
            XCTAssertTrue(plan(0x2800, c).isEmpty)
        }
    }

    // MARK: - 2 · Edge contact

    private struct Claims { let up, down, left, right: Bool }

    private func armClaims(_ cp: UInt32) -> Claims? {
        guard let a = TerminalBoxGlyphs.arms(for: cp) else { return nil }
        return Claims(up: a.up > 0, down: a.down > 0,
                      left: a.left > 0, right: a.right > 0)
    }

    /// What kind of band a glyph's ink occupies at each edge it touches:
    /// the single canonical bar, or one of the double pair. `.none` means
    /// the edge is not touched at all.
    private enum Band { case none, single, double }

    private static let doubleSpec: [UInt32: (up: Band, down: Band, left: Band, right: Band)] = [
        0x2550: (.none, .none, .double, .double),      // ═
        0x2551: (.double, .double, .none, .none),      // ║
        0x2552: (.none, .single, .none, .double),      // ╒
        0x2553: (.none, .double, .none, .single),      // ╓
        0x2554: (.none, .double, .none, .double),      // ╔
        0x2555: (.none, .single, .double, .none),      // ╕
        0x2556: (.none, .double, .single, .none),      // ╖
        0x2557: (.none, .double, .double, .none),      // ╗
        0x2558: (.single, .none, .none, .double),      // ╘
        0x2559: (.double, .none, .none, .single),      // ╙
        0x255A: (.double, .none, .none, .double),      // ╚
        0x255B: (.single, .none, .double, .none),      // ╛
        0x255C: (.double, .none, .single, .none),      // ╜
        0x255D: (.double, .none, .double, .none),      // ╝
        0x255E: (.single, .single, .none, .double),    // ╞
        0x255F: (.double, .double, .none, .single),    // ╟
        0x2560: (.double, .double, .none, .double),    // ╠
        0x2561: (.single, .single, .double, .none),    // ╡
        0x2562: (.double, .double, .single, .none),    // ╢
        0x2563: (.double, .double, .double, .none),    // ╣
        0x2564: (.none, .single, .double, .double),    // ╤
        0x2565: (.none, .double, .single, .single),    // ╥
        0x2566: (.none, .double, .double, .double),    // ╦
        0x2567: (.single, .none, .double, .double),    // ╧
        0x2568: (.double, .none, .single, .single),    // ╨
        0x2569: (.double, .none, .double, .double),    // ╩
        0x256A: (.single, .single, .double, .double),  // ╪
        0x256B: (.double, .double, .single, .single),  // ╫
        0x256C: (.double, .double, .double, .double),  // ╬
    ]

    func testArmsAndDoublesTouchExactlyTheirClaimedEdges() {
        sweep { c in
            var cases: [(UInt32, Claims)] = []
            for cp in Self.synthesized {
                if let claims = armClaims(cp) { cases.append((cp, claims)) }
                if let d = Self.doubleSpec[cp] {
                    cases.append((cp, Claims(up: d.up != .none, down: d.down != .none,
                                             left: d.left != .none, right: d.right != .none)))
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

    /// Doubles and hybrids: every edge-touching bar lands on the band its
    /// spec names — one of ║/═'s pair for a double edge, the canonical
    /// single band for a single one. That equality is what lets a ╪
    /// continue into the │ above it AND the ═ beside it.
    func testDoubleEdgeInkSitsOnItsSpecifiedBands() {
        sweep { c in
            let vb = doubleVBands(c), hb = doubleHBands(c)
            func vOK(_ xr: ClosedRange<Double>, _ kind: Band) -> Bool {
                switch kind {
                case .none: return false
                case .single: return near(xr, vband(1, c))
                case .double: return vb.contains { near(xr, $0) }
                }
            }
            func hOK(_ yr: ClosedRange<Double>, _ kind: Band) -> Bool {
                switch kind {
                case .none: return false
                case .single: return near(yr, hband(1, c))
                case .double: return hb.contains { near(yr, $0) }
                }
            }
            for (cp, spec) in Self.doubleSpec {
                let name = String(format: "U+%04X", cp)
                for r in fills(plan(cp, c)) {
                    let xr = r.left...r.right, yr = r.top...r.bottom
                    if near(r.top, c.y) {
                        XCTAssertTrue(vOK(xr, spec.up), "\(name) up band \(xr)")
                    }
                    if near(r.bottom, c.y + c.h) {
                        XCTAssertTrue(vOK(xr, spec.down), "\(name) down band \(xr)")
                    }
                    if near(r.left, c.x) {
                        XCTAssertTrue(hOK(yr, spec.left), "\(name) left band \(yr)")
                    }
                    if near(r.right, c.x + c.w) {
                        XCTAssertTrue(hOK(yr, spec.right), "\(name) right band \(yr)")
                    }
                }
            }
        }
    }

    // MARK: - 5b · Diagonals

    /// The diagonals overshoot their corners by one thickness along the
    /// diagonal — the overlap that keeps two adjacent cells' strokes from
    /// pinching where they meet — and run corner to corner at the cell's
    /// exact slope.
    func testDiagonalsOvershootTheirCorners() {
        sweep { c in
            let t = TerminalBoxGlyphs.thickness(1, c.scale)
            let len = (c.w * c.w + c.h * c.h).squareRoot()
            let ox = t * c.w / len, oy = t * c.h / len
            for cp in [UInt32(0x2571), 0x2572, 0x2573] {
                let name = String(format: "U+%04X", cp)
                let ops = plan(cp, c)
                XCTAssertEqual(ops.count, cp == 0x2573 ? 2 : 1, name)
                var kinds = Set<Bool>()          // true = rising ╱
                for op in ops {
                    guard case .stroke(let from, let segments, let th) = op,
                          segments.count == 1,
                          case .line(let to) = segments[0] else {
                        return XCTFail("\(name): not a single-segment stroke")
                    }
                    XCTAssertTrue(near(th, t), name)
                    let rising = from.dy > to.dy
                    kinds.insert(rising)
                    if rising {
                        XCTAssertTrue(near(from.dx, c.x - ox)
                                        && near(from.dy, c.y + c.h + oy), name)
                        XCTAssertTrue(near(to.dx, c.x + c.w + ox)
                                        && near(to.dy, c.y - oy), name)
                    } else {
                        XCTAssertTrue(near(from.dx, c.x - ox)
                                        && near(from.dy, c.y - oy), name)
                        XCTAssertTrue(near(to.dx, c.x + c.w + ox)
                                        && near(to.dy, c.y + c.h + oy), name)
                    }
                }
                switch cp {
                case 0x2571: XCTAssertEqual(kinds, [true], name)
                case 0x2572: XCTAssertEqual(kinds, [false], name)
                default:     XCTAssertEqual(kinds, [true, false], name)
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

    // MARK: - 4b · Dashes

    /// A dash is a broken bar: the right segment count, every segment on the
    /// canonical band of its weight, and — the defining property — touching
    /// NO cell edge, or it would read as a solid line.
    func testDashesAreBrokenBarsOnTheirBands() {
        let dashes: [UInt32: (n: Int, weight: Int, horizontal: Bool)] = [
            0x2504: (3, 1, true), 0x2505: (3, 2, true),
            0x2506: (3, 1, false), 0x2507: (3, 2, false),
            0x2508: (4, 1, true), 0x2509: (4, 2, true),
            0x250A: (4, 1, false), 0x250B: (4, 2, false),
            0x254C: (2, 1, true), 0x254D: (2, 2, true),
            0x254E: (2, 1, false), 0x254F: (2, 2, false),
        ]
        sweep { c in
            for (cp, d) in dashes {
                let name = String(format: "U+%04X", cp)
                let rs = fills(plan(cp, c))
                XCTAssertEqual(rs.count, d.n, name)
                for r in rs {
                    if d.horizontal {
                        XCTAssertTrue(near(r.top...r.bottom, hband(d.weight, c)),
                                      "\(name) band")
                        XCTAssertGreaterThan(r.left, c.x, name)
                        XCTAssertLessThan(r.right, c.x + c.w, name)
                    } else {
                        XCTAssertTrue(near(r.left...r.right, vband(d.weight, c)),
                                      "\(name) band")
                        XCTAssertGreaterThan(r.top, c.y, name)
                        XCTAssertLessThan(r.bottom, c.y + c.h, name)
                    }
                }
            }
        }
    }

    // MARK: - 4c · Braille

    /// The bit mapping is the Unicode one — dot k is bit k-1, dots 1-3 down
    /// the left column, 4-6 down the right, 7-8 the bottom pair — and every
    /// dot lies inside its cell with its whole radius.
    func testBrailleDots() {
        let grid: [(col: Double, row: Double)] = [(0, 0), (0, 1), (0, 2),
                                                  (1, 0), (1, 1), (1, 2),
                                                  (0, 3), (1, 3)]
        sweep { c in
            for cp in UInt32(0x2800)...UInt32(0x28FF) {
                let name = String(format: "U+%04X", cp)
                let bits = cp - 0x2800
                var dots: [(Offset, Double)] = []
                for op in plan(cp, c) {
                    guard case .disc(let centre, let radius) = op else {
                        return XCTFail("\(name): non-disc op")
                    }
                    dots.append((centre, radius))
                }
                XCTAssertEqual(dots.count, bits.nonzeroBitCount, name)
                var expected = Set<Int>()
                for bit in 0..<8 where bits & (1 << bit) != 0 { expected.insert(bit) }
                for (centre, radius) in dots {
                    XCTAssertGreaterThan(radius, 0, name)
                    XCTAssertGreaterThanOrEqual(centre.dx - radius, c.x, name)
                    XCTAssertLessThanOrEqual(centre.dx + radius, c.x + c.w, name)
                    XCTAssertGreaterThanOrEqual(centre.dy - radius, c.y, name)
                    XCTAssertLessThanOrEqual(centre.dy + radius, c.y + c.h, name)
                    let bit = grid.firstIndex {
                        near(centre.dx, c.x + c.w * (0.25 + 0.5 * $0.col))
                            && near(centre.dy, c.y + c.h * (0.125 + 0.25 * $0.row))
                    }
                    XCTAssertNotNil(bit, "\(name) dot off the grid")
                    if let bit { XCTAssertTrue(expected.remove(bit) != nil, name) }
                }
                XCTAssertTrue(expected.isEmpty, "\(name) missing dots \(expected)")
            }
        }
    }

    // MARK: - 4d · Powerline

    /// The solid separators hard-attach to one cell edge for the full height
    /// — the flush transition is the whole point — and reach the opposite
    /// edge at the vertical midline. Paths are continuous like the corners.
    func testPowerlineSeparators() {
        // (attached edge is left?, solid?)
        let claims: [UInt32: (attachedLeft: Bool, solid: Bool)] = [
            0xE0B0: (true, true), 0xE0B1: (true, false),
            0xE0B2: (false, true), 0xE0B3: (false, false),
            0xE0B4: (true, true), 0xE0B5: (true, false),
            0xE0B6: (false, true), 0xE0B7: (false, false),
        ]
        sweep { c in
            for (cp, claim) in claims {
                let name = String(format: "U+%04X", cp)
                let ops = plan(cp, c)
                XCTAssertEqual(ops.count, 1, name)
                let from: Offset
                let segments: [BoxStroke]
                switch ops[0] {
                case .fillPath(let f, let s):
                    XCTAssertTrue(claim.solid, name)
                    from = f; segments = s
                case .stroke(let f, let s, let t):
                    XCTAssertFalse(claim.solid, name)
                    XCTAssertTrue(near(t, TerminalBoxGlyphs.thickness(1, c.scale)), name)
                    from = f; segments = s
                default:
                    return XCTFail("\(name): unexpected op")
                }
                let edge = claim.attachedLeft ? c.x : c.x + c.w
                let far = claim.attachedLeft ? c.x + c.w : c.x
                // Starts at the attached edge's top corner…
                XCTAssertTrue(near(from.dx, edge) && near(from.dy, c.y), name)
                // …walks continuously…
                var at = from
                var apexes: [Offset] = []
                for segment in segments {
                    switch segment {
                    case .line(let to):
                        at = to
                        apexes.append(to)
                    case .arc(let oval, let start, let sweepAngle):
                        let cx = (oval.left + oval.right) / 2
                        let cy = (oval.top + oval.bottom) / 2
                        let rx = (oval.right - oval.left) / 2
                        let ry = (oval.bottom - oval.top) / 2
                        let s = Offset(cx + rx * cos(start), cy + ry * sin(start))
                        XCTAssertTrue(near(s.dx, at.dx) && near(s.dy, at.dy), name)
                        // The arc's extreme point must reach the far edge.
                        let mid = start + sweepAngle / 2
                        apexes.append(Offset(cx + rx * cos(mid), cy + ry * sin(mid)))
                        at = Offset(cx + rx * cos(start + sweepAngle),
                                    cy + ry * sin(start + sweepAngle))
                    }
                }
                // …and ends at the attached edge's bottom corner.
                XCTAssertTrue(near(at.dx, edge) && near(at.dy, c.y + c.h), name)
                // Something along the way reached the far edge at the midline.
                XCTAssertTrue(apexes.contains {
                    near($0.dx, far) && near($0.dy, c.y + c.h / 2)
                }, "\(name) never reaches the far edge")
            }
        }
    }

    // MARK: - 4e · Mosaics

    /// Reconstruct a mosaic's bitmask from its plan: every rect must be
    /// exactly one cell of the 2xN grid, no cell twice. nil = malformed.
    private func mosaicMask(_ cp: UInt32, _ c: Cell, rows: Int) -> UInt32? {
        var mask: UInt32 = 0
        let xm = c.x + c.w / 2
        for r in fills(plan(cp, c)) {
            let colIdx: Int
            if near(r.left, c.x) && near(r.right, xm) { colIdx = 0 }
            else if near(r.left, xm) && near(r.right, c.x + c.w) { colIdx = 1 }
            else { return nil }
            var rowIdx = -1
            for row in 0..<rows {
                if near(r.top, c.y + c.h * Double(row) / Double(rows))
                    && near(r.bottom, c.y + c.h * Double(row + 1) / Double(rows)) {
                    rowIdx = row
                    break
                }
            }
            if rowIdx < 0 { return nil }
            let bit = UInt32(1) << (rowIdx * 2 + colIdx)
            if mask & bit != 0 { return nil }
            mask |= bit
        }
        return mask
    }

    /// Sextants: 60 distinct 2x3 masks, and the exclusion law — never empty,
    /// full, or a half-block, because those shapes live in U+2580's block
    /// and the codepoint range skips them.
    func testSextantMosaics() {
        sweep { c in
            var seen = Set<UInt32>()
            for cp in UInt32(0x1FB00)...UInt32(0x1FB3B) {
                let name = String(format: "U+%04X", cp)
                guard let mask = mosaicMask(cp, c, rows: 3) else {
                    return XCTFail("\(name): rects off the 2x3 grid")
                }
                XCTAssertTrue(seen.insert(mask).inserted, "\(name) duplicate")
                XCTAssertFalse([0, 0b111111, 0b010101, 0b101010].contains(mask), name)
            }
            XCTAssertEqual(mosaicMask(0x1FB00, c, rows: 3), 1)          // 🬀 cell 1
            XCTAssertEqual(mosaicMask(0x1FB3B, c, rows: 3), 0b111110)   // 🬻 all but 1
        }
    }

    /// Octants: 230 distinct 2x4 masks, and the exclusion law — nothing a
    /// quadrant combination, half, or quarter block already draws.
    func testOctantMosaics() {
        var excluded: Set<UInt32> = [0x03, 0x3F, 0xC0, 0xFC]  // ¼/¾ blocks
        for q in 0...15 {                                     // quadrant unions
            var m: UInt32 = 0
            if q & 1 != 0 { m |= 0x05 }
            if q & 2 != 0 { m |= 0x0A }
            if q & 4 != 0 { m |= 0x50 }
            if q & 8 != 0 { m |= 0xA0 }
            excluded.insert(m)
        }
        sweep { c in
            var seen = Set<UInt32>()
            for cp in UInt32(0x1CD00)...UInt32(0x1CDE5) {
                let name = String(format: "U+%05X", cp)
                guard let mask = mosaicMask(cp, c, rows: 4) else {
                    return XCTFail("\(name): rects off the 2x4 grid")
                }
                XCTAssertTrue(seen.insert(mask).inserted, "\(name) duplicate")
                XCTAssertFalse(excluded.contains(mask), "\(name) is an excluded shape")
            }
            XCTAssertEqual(mosaicMask(0x1CD00, c, rows: 4), 0x04)  // OCTANT-3
            XCTAssertEqual(mosaicMask(0x1CDE5, c, rows: 4), 0xFE)  // OCTANT-2345678
        }
    }

    /// The positional eighth blocks: expected coverage written independently
    /// from the chart, fractions of the cell.
    func testLegacyEighthBlocks() {
        typealias F = (Double, Double, Double, Double)
        var expect: [UInt32: [F]] = [:]
        for n in 0..<6 {                                   // vertical eighths 2-7
            let k = Double(n + 1)
            expect[UInt32(0x1FB70 + n)] = [(k / 8, 0, (k + 1) / 8, 1)]
        }
        for n in 0..<6 {                                   // horizontal eighths 2-7
            let k = Double(n + 1)
            expect[UInt32(0x1FB76 + n)] = [(0, k / 8, 1, (k + 1) / 8)]
        }
        let leftCol: F = (0, 0, 1.0 / 8, 1), rightCol: F = (7.0 / 8, 0, 1, 1)
        let topRow: F = (0, 0, 1, 1.0 / 8), bottomRow: F = (0, 7.0 / 8, 1, 1)
        expect[0x1FB7C] = [leftCol, bottomRow]
        expect[0x1FB7D] = [leftCol, topRow]
        expect[0x1FB7E] = [rightCol, topRow]
        expect[0x1FB7F] = [rightCol, bottomRow]
        expect[0x1FB80] = [topRow, bottomRow]
        expect[0x1FB81] = [topRow, (0, 2.0 / 8, 1, 3.0 / 8),
                           (0, 4.0 / 8, 1, 5.0 / 8), bottomRow]
        for (i, k) in [2.0, 3, 5, 6, 7].enumerated() {
            expect[UInt32(0x1FB82 + i)] = [(0, 0, 1, k / 8)]           // upper k/8
            expect[UInt32(0x1FB87 + i)] = [((8 - k) / 8, 0, 1, 1)]     // right k/8
        }
        sweep { c in
            for (cp, frs) in expect {
                let name = String(format: "U+%05X", cp)
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
            for cp in UInt32(0x1FB8C)...UInt32(0x1FB8F) {              // half shades
                guard case .shade(_, let f)? = plan(cp, c).first else {
                    return XCTFail(String(format: "U+%05X not a shade", cp))
                }
                XCTAssertEqual(f, 0.5)
            }
        }
    }

    // MARK: - 4f · Wedges and triangles

    /// The smooth mosaics are single filled polygons whose every vertex lies
    /// on the wedge lattice — x at {0, ½, 1}, y at {0, ⅓, ⅔, 1} — with the
    /// vertex sets distinct across the range.
    func testWedgePolygons() {
        sweep { c in
            var seen = Set<[Int]>()
            for cp in UInt32(0x1FB3C)...UInt32(0x1FB67) {
                let name = String(format: "U+%05X", cp)
                let ops = plan(cp, c)
                XCTAssertEqual(ops.count, 1, name)
                guard case .fillPath(let from, let segments) = ops[0] else {
                    return XCTFail("\(name): not a filled polygon")
                }
                var poly = [from]
                for s in segments {
                    guard case .line(let to) = s else {
                        return XCTFail("\(name): non-line segment")
                    }
                    poly.append(to)
                }
                XCTAssertGreaterThanOrEqual(poly.count, 3, name)
                var key: [Int] = []
                for p in poly {
                    let xi = [c.x, c.x + c.w / 2, c.x + c.w].firstIndex { near($0, p.dx) }
                    let yi = [c.y, c.y + c.h / 3, c.y + 2 * c.h / 3, c.y + c.h]
                        .firstIndex { near($0, p.dy) }
                    XCTAssertNotNil(xi, "\(name) x off lattice: \(p.dx)")
                    XCTAssertNotNil(yi, "\(name) y off lattice: \(p.dy)")
                    key.append((xi ?? -1) * 10 + (yi ?? -1))
                }
                XCTAssertTrue(seen.insert(key).inserted, "\(name) duplicate shape")
            }
            // 🬼 is the small lower-left triangle: left ⅔ → corner → bottom ½.
            if case .fillPath(let f, let segs)? = plan(0x1FB3C, c).first {
                XCTAssertTrue(near(f.dx, c.x) && near(f.dy, c.y + 2 * c.h / 3))
                XCTAssertEqual(segs.count, 2)
            } else { XCTFail("U+1FB3C") }
        }
    }

    /// The quarter triangles point at the exact cell centre, and each
    /// three-quarter block is the cell minus the matching triangle — five
    /// vertices, sharing the triangle's centre point.
    func testCentreTriangles() {
        sweep { c in
            for cp in UInt32(0x1FB68)...UInt32(0x1FB6F) {
                let name = String(format: "U+%05X", cp)
                guard case .fillPath(let from, let segments)? = plan(cp, c).first else {
                    return XCTFail("\(name): not a filled polygon")
                }
                var poly = [from]
                for s in segments {
                    if case .line(let to) = s { poly.append(to) }
                }
                XCTAssertEqual(poly.count, cp <= 0x1FB6B ? 5 : 3, name)
                XCTAssertTrue(poly.contains {
                    near($0.dx, c.x + c.w / 2) && near($0.dy, c.y + c.h / 2)
                }, "\(name) misses the centre")
                for p in poly where !(near(p.dx, c.x + c.w / 2) && near(p.dy, c.y + c.h / 2)) {
                    let corner = (near(p.dx, c.x) || near(p.dx, c.x + c.w))
                        && (near(p.dy, c.y) || near(p.dy, c.y + c.h))
                    XCTAssertTrue(corner, "\(name) vertex \(p) is neither centre nor corner")
                }
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
