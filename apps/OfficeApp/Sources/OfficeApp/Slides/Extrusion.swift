// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

/// A shape with depth (`a:sp3d extrusionH`) seen through `a:scene3d`'s
/// camera: its outline swept back into a solid, turned, and drawn face by
/// face, far ones first, each in the shape's colour lit by how it faces.
///
/// What this is not: PowerPoint's renderer. There are no bevels, no
/// materials and two measured light rigs, and a perspective camera is drawn as
/// the parallel one that looks along the same line — the solid's outline
/// and which sides show are right, its shading is plausible.
enum Extrusion {
    /// The cameras by name, as latitude, longitude and revolution in
    /// degrees — what `a:camera prst` stands for when it has no `a:rot`.
    private static let cameras: [String: (Double, Double, Double)] = [
        "isometricLeftDown": (35.4, 45, 0), "isometricRightUp": (35.4, 315, 0),
        "isometricTopUp": (314.7, 315.1, 59.8), "isometricTopDown": (314.7, 44.9, 300.2),
        "isometricOffAxis1Left": (18, 64, 0), "isometricOffAxis1Right": (18, 334, 0),
        "isometricOffAxis1Top": (301.3, 306.5, 57.6), "isometricOffAxis2Left": (18, 26, 0),
        "isometricOffAxis2Right": (18, 296, 0), "isometricOffAxis2Top": (301.3, 53.5, 302.4),
        "perspectiveLeft": (0, 20, 0), "perspectiveRight": (0, 340, 0),
        "perspectiveAbove": (340, 0, 0), "perspectiveBelow": (20, 0, 0),
        "perspectiveRelaxed": (309.6, 0, 0), "perspectiveRelaxedModerately": (324.8, 0, 0),
        "perspectiveContrastingLeftFacing": (10.4, 43.5, 358.8),
        "perspectiveContrastingRightFacing": (10.4, 316.5, 1.2),
        "perspectiveHeroicExtremeLeftFacing": (8.1, 34.5, 357.1),
        "perspectiveHeroicExtremeRightFacing": (8.1, 325.5, 2.9),
    ]

    /// The slide of an oblique camera per unit of depth: the back of the
    /// solid shows on the side the camera is named for.
    private static func oblique(_ name: String) -> Offset? {
        let n = name.lowercased()
        guard n.containsSubstring("oblique") || n.hasPrefix("legacyperspective") else { return nil }
        // Measured on PowerPoint's pages: a fifth of the depth each way for
        // the oblique cameras, more for the legacy ones.
        let k = n.hasPrefix("legacyperspective") ? 0.6 : n.hasPrefix("legacy") ? 0.35 : 0.21
        let dx = n.hasSuffix("left") ? -k : n.hasSuffix("right") ? k : 0
        let dy = n.containsSubstring("top") ? -k : n.containsSubstring("bottom") ? k : 0
        return dx == 0 && dy == 0 ? nil : Offset(dx, dy)
    }

    static func read(_ spPr: XNode?, colors: ColorContext) -> Scene3D? {
        let sp3d = spPr?.first("a:sp3d")
        var s = Scene3D(depth: max(0, sp3d?["extrusionH"].flatMap(Double.init) ?? 0) / Pptx.emu)
        s.extrusionColor = sp3d?.first("a:extrusionClr").flatMap(colors.color(in:))
        s.wireframe = sp3d?["prstMaterial"] == "legacyWireframe"
        if let camera = spPr?.first("a:scene3d")?.first("a:camera") {
            let name = camera["prst"] ?? ""
            s.perspective = name.hasPrefix("legacyPerspective")
            s.oblique = s.depth > 0 ? oblique(name) : nil
            if let c = cameras[name] { (s.lat, s.lon, s.rev) = c }
            s.legacy = name.hasPrefix("legacy")
            if let rot = camera.first("a:rot") {
                func deg(_ a: String) -> Double { (rot[a].flatMap(Double.init) ?? 0) / 60000 }
                (s.lat, s.lon, s.rev) = (deg("lat"), deg("lon"), deg("rev"))
            }
        }
        if let rig = spPr?.first("a:scene3d")?.first("a:lightRig") {
            s.rig = rig["rig"] ?? "threePt"
            let turns: [String: Double] = ["t": 0, "tr": 45, "r": 90, "br": 135, "b": 180, "bl": 225, "l": 270, "tl": 315]
            s.rigTurn = turns[rig["dir"] ?? "t"] ?? 0
        }
        // Looked at square on, a solid is its own front.
        if s.oblique == nil, s.lat == 0, s.lon == 0, s.rev == 0 { return nil }
        return s
    }

    private struct P3 { var x, y, z: Double }

    /// The outline as closed runs of points, a curve as short chords.
    private static func contours(_ path: Path) -> [[Offset]] {
        var out: [[Offset]] = []
        for metric in path.computeMetrics() {
            let n = max(8, min(400, Int(metric.length / 3)))
            var pts: [Offset] = []
            for i in 0 ..< n {
                if let t = metric.getTangentForOffset(metric.length * Double(i) / Double(n)) { pts.append(t.position) }
            }
            if pts.count >= 3 { out.append(pts) }
        }
        return out
    }

    /// Draws `shape` as its solid. `outline` is the shape's outline in the
    /// canvas's space (`r` its frame). False when there is nothing to
    /// draw this way, and the shape is then drawn flat.
    static func paint(_ shape: SlideShape, outline: Path, _ r: Rect, _ canvas: any Canvas, pxPerPt px: Double) -> Bool {
        guard let scene = shape.scene3d, !scene.isFlatTurn, let fill = shape.fill ?? shape.fillStyle?.stops.first?.color ?? shape.fillStyle?.color else { return false }
        let rings = contours(outline)
        guard !rings.isEmpty else { return false }
        let c = r.center
        let depth = scene.depth * px
        // The camera turns one way; what is seen turns the other.
        let lat = -scene.lat * .pi / 180, lon = -scene.lon * .pi / 180, rev = -scene.rev * .pi / 180
        func turn(_ p: P3) -> P3 {
            // About the vertical axis, then the horizontal, then the line of sight.
            var q = P3(x: p.x * cos(lon) + p.z * sin(lon), y: p.y, z: -p.x * sin(lon) + p.z * cos(lon))
            q = P3(x: q.x, y: q.y * cos(lat) - q.z * sin(lat), z: q.y * sin(lat) + q.z * cos(lat))
            return P3(x: q.x * cos(rev) - q.y * sin(rev), y: q.x * sin(rev) + q.y * cos(rev), z: q.z)
        }
        func place(_ p: Offset, _ z: Double) -> P3 {
            var q = turn(P3(x: p.dx - c.dx, y: p.dy - c.dy, z: z))
            // An oblique camera: what lies behind slides aside as it recedes
            // — and, in perspective, draws in toward a point as it goes.
            if let o = scene.oblique {
                let f = scene.perspective ? 250 * px / (250 * px + max(0, -q.z)) : 1
                q.x = q.x * f - o.dx * q.z * f
                q.y = q.y * f - o.dy * q.z * f
            }
            return q
        }
        func flat(_ p: P3) -> Offset { Offset(c.dx + p.x, c.dy + p.y) }
        // z runs toward the eye: the front at 0, the back `depth` behind.
        let front = rings.map { $0.map { place($0, 0) } }
        let back = rings.map { $0.map { place($0, -depth) } }

        // The sides are the colour the file names, else the outline's where
        // the shape has one (PowerPoint's "automatic" depth colour), else
        // the fill's.
        let side = scene.extrusionColor ?? shape.outline ?? fill
        // PowerPoint's rigs light the shape in its own frame (x right, y
        // down, z out of the slide), so a face is as bright whatever the
        // camera: an ambient share and lights given as direction times
        // strength, for `dir="t"`. Read off PowerPoint's prints of the
        // Scene3d decks — threePt (its default) leaves a face turned right
        // at 0.12 of its colour, up and right 0.30, up 0.74, left 0.69 and
        // the front 1.04; harsh lights the left at 1.51, the top 0.80 and
        // the front 0.83, and `dir="r"` moves that light to the top and
        // brings one from below round to the left (0.86). Other rigs are
        // drawn as threePt.
        let rig: (ambient: Double, lights: [P3]) = scene.rig == "harsh"
            ? (0.1, [P3(x: -1.41, y: -0.7, z: 0.43), P3(x: 0, y: 0.76, z: 0.3)])
            : (0.12, [P3(x: -0.37, y: -0.62, z: 0.6), P3(x: -0.2, y: 0, z: 0.32)])
        let turnRig = scene.rigTurn * .pi / 180
        let lights = rig.lights.map { l in
            P3(x: l.x * cos(turnRig) - l.y * sin(turnRig), y: l.x * sin(turnRig) + l.y * cos(turnRig), z: l.z)
        }
        func litLocal(_ base: Color, _ n: P3) -> Color {
            let len = max(1e-9, (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot())
            var k = rig.ambient
            for l in lights { k += max(0, (n.x * l.x + n.y * l.y + n.z * l.z) / len) }
            func ch(_ v: Int) -> Int { max(0, min(255, Int((Double(v) * k).rounded()))) }
            return Color(argb: base.alpha, ch(base.red), ch(base.green), ch(base.blue))
        }
        func lit(_ base: Color, _ n: P3) -> Color {
            // One light, in front and a little to the left and below — the
            // side PowerPoint's default rig leaves a top face darkest.
            let l = P3(x: -0.45, y: 0.25, z: 0.86)
            let len = max(1e-9, (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot())
            let d = max(0, (n.x * l.x + n.y * l.y + n.z * l.z) / len)
            let k = 0.25 + 0.8 * d
            func ch(_ v: Int) -> Int { max(0, min(255, Int((Double(v) * k).rounded()))) }
            return Color(argb: base.alpha, ch(base.red), ch(base.green), ch(base.blue))
        }
        func polygon(_ pts: [Offset], _ color: Color) {
            let path = Path()
            path.addPolygon(pts, true)
            let p = Paint()
            p.style = .fill
            p.isAntiAlias = true
            p.color = color
            canvas.drawPath(path, p)
            // Its own edge too, so two faces meeting leave no hairline between.
            p.style = .stroke
            p.strokeWidth = 0.6
            canvas.drawPath(path, p)
        }
        func face(_ rings3: [[P3]], _ color: Color, edge: Color?) {
            let path = Path()
            path.fillType = .evenOdd
            for ring in rings3 { path.addPolygon(ring.map(flat), true) }
            let p = Paint()
            p.style = .fill
            p.isAntiAlias = true
            p.color = color
            canvas.drawPath(path, p)
            if let edge {
                p.style = .stroke
                p.strokeWidth = max(0.5, shape.outlineWidth * px)
                p.color = edge
                canvas.drawPath(path, p)
            }
        }
        if scene.wireframe {
            // Edges only: the two faces' outlines and the corners between.
            let p = Paint()
            p.style = .stroke
            p.isAntiAlias = true
            p.strokeWidth = max(0.5, 0.5 * px)
            p.color = Color(0xFFBFBFBF)
            for (ri, ring) in front.enumerated() {
                for rings3 in [ring, back[ri]] {
                    let path = Path()
                    path.addPolygon(rings3.map(flat), true)
                    canvas.drawPath(path, p)
                }
                // A corner is where the outline turns sharply.
                for i in ring.indices {
                    let a = ring[(i + ring.count - 1) % ring.count], b = ring[i], d = ring[(i + 1) % ring.count]
                    let u = Offset(b.x - a.x, b.y - a.y), v = Offset(d.x - b.x, d.y - b.y)
                    let cross = abs(u.dx * v.dy - u.dy * v.dx), dot = u.dx * v.dx + u.dy * v.dy
                    if atan2(cross, dot) > 0.5 { canvas.drawLine(flat(b), flat(back[ri][i]), p) }
                }
            }
            return true
        }
        // Which way the front faces: toward the eye, or — turned past a
        // right angle — away, and then the back is what is seen.
        let n0 = turn(P3(x: 0, y: 0, z: 1))
        let frontShows = n0.z + n0.x * (scene.oblique?.dx ?? 0) + n0.y * (scene.oblique?.dy ?? 0) >= 0
        face(frontShows ? back : front, scene.legacy ? lit(side, P3(x: -n0.x, y: -n0.y, z: -abs(n0.z))) : litLocal(side, P3(x: 0, y: 0, z: frontShows ? -1 : 1)), edge: nil)
        // The sides, far ones first.
        var quads: [(z: Double, pts: [Offset], color: Color)] = []
        for (ri, ring) in front.enumerated() {
            let far = back[ri]
            for i in ring.indices {
                let j = (i + 1) % ring.count
                let a = ring[i], b = ring[j], a2 = far[i], b2 = far[j]
                // The side's normal: across its edge and its depth.
                let u = P3(x: b.x - a.x, y: b.y - a.y, z: b.z - a.z), v = P3(x: a2.x - a.x, y: a2.y - a.y, z: a2.z - a.z)
                var n = P3(x: u.y * v.z - u.z * v.y, y: u.z * v.x - u.x * v.z, z: u.x * v.y - u.y * v.x)
                if n.z < 0 { n = P3(x: -n.x, y: -n.y, z: -n.z) }
                // The same side in the shape's own frame: across its edge
                // in the outline, the way that faces the eye.
                let e = Offset(rings[ri][j].dx - rings[ri][i].dx, rings[ri][j].dy - rings[ri][i].dy)
                var local = P3(x: e.dy, y: -e.dx, z: 0)
                let seen = turn(local)
                if seen.x * n.x + seen.y * n.y + seen.z * n.z < 0 { local = P3(x: -local.x, y: -local.y, z: 0) }
                quads.append(((a.z + b.z + a2.z + b2.z) / 4, [flat(a), flat(b), flat(b2), flat(a2)],
                              scene.legacy ? lit(side, n) : litLocal(side, local)))
            }
        }
        for q in quads.sorted(by: { $0.z < $1.z }) { polygon(q.pts, q.color) }
        // The face itself is in full light, a touch over the flat colour.
        func bright(_ c: Color) -> Color {
            func ch(_ v: Int) -> Int { min(255, Int((Double(v) * 1.1).rounded())) }
            return Color(argb: c.alpha, ch(c.red), ch(c.green), ch(c.blue))
        }
        // Seen from behind, it is the back that shows, and that is unlit.
        func dark(_ c: Color) -> Color {
            Color(argb: c.alpha, Int(Double(c.red) * 0.3), Int(Double(c.green) * 0.3), Int(Double(c.blue) * 0.3))
        }
        let shown = !frontShows ? dark(side) : scene.legacy ? bright(fill) : litLocal(fill, P3(x: 0, y: 0, z: 1))
        face(frontShows ? front : back, shown, edge: frontShows ? shape.outline : nil)
        return true
    }
}
