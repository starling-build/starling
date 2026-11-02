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

    /// PowerPoint's light rigs, as printed (test/labs/p3d, Lab A: a slab under
    /// `isometricOffAxis1Right`, fill 199,100,50, every rig at dir t/r/b/l).
    /// The lights sit in the shape's own frame, so a face's brightness is a
    /// function of how it faces the shape, not the camera: `front` is the
    /// face's multiple of its colour, and `walls` the four a side wall takes
    /// as it faces right, down, left, up (azimuth 0, 90, 180, 270 in the
    /// shape's frame, y down) at `dir="t"` — each as red, green, blue
    /// multiples and an additive share of white (the specular band). `dir`
    /// turns the rig a quarter round per step (t, r, b, l); between the four
    /// a wall is read off a smooth curve through them.
    struct Rig {
        var front: (Double, Double, Double)
        var walls: [(Double, Double, Double, Double)]
    }
    static let rigs: [String: Rig] = [
        "threePt": Rig(front: (1.04, 1.04, 1.04), walls: [(0.12, 0.12, 0.12, 0.00), (1.00, 1.00, 1.00, 0.05), (0.60, 0.60, 0.60, 0.20), (0.74, 0.74, 0.74, 0.00)]),
        "balanced": Rig(front: (0.96, 0.96, 0.96), walls: [(0.85, 0.85, 0.85, 0.03), (0.73, 0.73, 0.73, 0.02), (0.56, 0.56, 0.56, 0.00), (1.08, 1.08, 1.08, 0.00)]),
        "soft": Rig(front: (0.97, 0.97, 0.97), walls: [(0.80, 0.80, 0.80, 0.00), (0.43, 0.43, 0.43, 0.00), (0.60, 0.60, 0.60, 0.00), (0.97, 0.97, 0.97, 0.00)]),
        "harsh": Rig(front: (0.84, 0.84, 0.84), walls: [(0.28, 0.28, 0.28, 0.00), (0.88, 0.88, 0.88, 0.00), (1.50, 1.50, 1.50, 0.00), (0.80, 0.80, 0.80, 0.00)]),
        "flood": Rig(front: (0.86, 0.86, 0.86), walls: [(0.20, 0.20, 0.20, 0.00), (0.76, 0.76, 0.76, 0.00), (2.02, 2.02, 2.02, 0.00), (0.88, 0.88, 0.88, 0.00)]),
        "contrasting": Rig(front: (1.00, 1.00, 1.00), walls: [(1.00, 1.00, 1.00, 0.00), (1.00, 1.00, 1.00, 0.00), (1.00, 1.00, 1.00, 0.00), (1.00, 1.00, 1.00, 0.00)]),
        "morning": Rig(front: (0.92, 0.92, 0.92), walls: [(0.95, 0.95, 0.95, 0.00), (1.08, 1.08, 1.08, 0.00), (1.30, 1.30, 1.30, 0.00), (0.31, 0.31, 0.31, 0.00)]),
        "sunrise": Rig(front: (0.91, 0.91, 0.91), walls: [(1.28, 1.28, 0.96, 0.00), (1.07, 1.07, 1.07, 0.00), (1.31, 1.31, 1.31, 0.00), (0.44, 0.44, 0.44, 0.00)]),
        "sunset": Rig(front: (0.98, 0.98, 0.98), walls: [(0.78, 0.78, 0.78, 0.00), (1.00, 0.56, 0.48, 0.00), (1.13, 0.66, 0.52, 0.00), (0.37, 0.37, 0.37, 0.00)]),
        "chilly": Rig(front: (0.99, 0.99, 0.99), walls: [(0.41, 0.41, 0.41, 0.02), (0.98, 0.98, 0.98, 0.02), (1.02, 1.02, 1.02, 0.02), (0.49, 0.49, 0.49, 0.01)]),
        "freezing": Rig(front: (0.60, 0.60, 0.60), walls: [(0.80, 0.80, 0.80, 0.12), (0.70, 0.70, 0.70, 0.06), (0.86, 0.86, 0.86, 0.07), (0.25, 0.25, 0.25, 0.03)]),
        "flat": Rig(front: (1.00, 1.00, 1.00), walls: [(0.94, 0.94, 0.94, 0.15), (0.97, 0.97, 0.97, 0.05), (1.00, 1.00, 1.00, 0.00), (1.00, 1.00, 1.00, 0.00)]),
        "twoPt": Rig(front: (1.00, 1.00, 1.00), walls: [(0.32, 0.32, 0.32, 0.00), (0.69, 0.69, 0.69, 0.00), (0.60, 0.60, 0.60, 0.00), (0.52, 0.52, 0.52, 0.00)]),
        "glow": Rig(front: (1.00, 1.00, 1.00), walls: [(1.70, 1.70, 1.70, 0.00), (1.00, 1.00, 1.00, 0.00), (1.98, 1.98, 1.98, 0.00), (1.00, 1.00, 1.00, 0.00)]),
        "brightRoom": Rig(front: (1.00, 1.00, 1.00), walls: [(1.98, 1.98, 1.98, 0.00), (1.50, 1.50, 1.50, 0.00), (2.50, 2.50, 2.50, 0.00), (1.50, 1.50, 1.50, 0.00)]),
    ]

    /// A face with normal `n` (shape frame, z out of the slide) lit by `rig`
    /// turned `turn` degrees: a wall (no z) from the curve round the four
    /// measured azimuths, the front from `front`, a slope between by how far
    /// it leans.
    /// What a material does to a wall under the twoPt rig, read off
    /// PowerPoint's print of oox-Scene3d_material_highlight (orthographic
    /// camera, light turned a quarter): the wall takes `diffuse` of its colour
    /// plus `floor` white everywhere, and on the half that faces up a
    /// highlight of `lobe` more white, centred `centre` degrees above the
    /// horizontal and `sigma` wide (a lobe above 1 blows out to white); `back`
    /// is the share of the fill the unlit back face keeps. PROVISIONAL: one
    /// deck, one rig, and only where the light is turned (modernCamera, turn 0,
    /// prints pure dark walls with no white floor: Lab D will say why).
    struct Material { var diffuse, floor, lobe, centre, sigma, back: Double }
    static func material(_ name: String) -> Material {
        switch name {
        case "legacyPlastic", "metal", "plastic": return Material(diffuse: 0.49, floor: 0.13, lobe: 1.1, centre: 20, sigma: 13, back: 0.25)
        case "matte", "legacyMatte": return Material(diffuse: 0.49, floor: 0.13, lobe: 0.07, centre: 25, sigma: 35, back: 0.25)
        case "dkEdge": return Material(diffuse: 0.47, floor: 0.11, lobe: 1.1, centre: 20, sigma: 13, back: 0.23)
        case "legacyMetal": return Material(diffuse: 0.31, floor: 0.12, lobe: 1.1, centre: 20, sigma: 14, back: 0.17)
        default: return Material(diffuse: 0.49, floor: 0.13, lobe: 0.41, centre: 25, sigma: 35, back: 0.25)
        }
    }

    /// The rigs as lights, for a rig that carries an `a:rot`: an ambient share
    /// and lights (direction in the rig's own frame, strength), fitted to Lab
    /// D (test/labs/p3d, 23 cells a rig, front and two walls). A face's share
    /// of its colour is `ambient + sum strength * max(0, n . R L)`, R the
    /// rig's rotation Ry(lon) Rx(lat) Rz(rev) (the angles as written), n the
    /// face's normal in the shape's frame. The fit is within 0.5% for harsh and
    /// soft, 1% flood, 2% threePt; a highlight's white is not in it. Without
    /// an `a:rot` the measured table above stands. `dir` does not matter once
    /// there is an `a:rot` (Lab D: dir r prints as dir t).
    static let rotatedRigs: [String: (ambient: Double, lights: [(P3, Double)])] = [
        "harsh": (0.28, [(P3(x: -35.4, y: -27.98, z: 15.63), 0.88), (P3(x: -19.02, y: 19.38, z: 8.78), 0.87)]),
        "soft": (0.69, [(P3(x: 0.77, y: -2.11, z: 2.1), 0.41), (P3(x: -0.35, y: 1.05, z: -1.06), -0.39)]),
        "flood": (0.14, [(P3(x: -2.17, y: 0.8, z: 0.42), 1.81), (P3(x: -0.46, y: -1.34, z: 0.83), 0.75), (P3(x: 3.28, y: -6.34, z: 0.51), 0.13)]),
        "threePt": (0.02, [(P3(x: -1.78, y: 5.23, z: -5.5), 1.07), (P3(x: 1.35, y: 3.02, z: 6.21), 0.51), (P3(x: -4.47, y: -9.76, z: 7.65), 0.96)]),
    ]

    /// `v` turned about the line of sight, then the horizontal axis, then the vertical.
    static func turned(_ v: P3, lat: Double, lon: Double, rev: Double) -> P3 {
        let (la, lo, re) = (lat * .pi / 180, lon * .pi / 180, rev * .pi / 180)
        var q = P3(x: v.x * cos(re) - v.y * sin(re), y: v.x * sin(re) + v.y * cos(re), z: v.z)
        q = P3(x: q.x, y: q.y * cos(la) - q.z * sin(la), z: q.y * sin(la) + q.z * cos(la))
        return P3(x: q.x * cos(lo) + q.z * sin(lo), y: q.y, z: -q.x * sin(lo) + q.z * cos(lo))
    }

    /// The share of its colour a face with normal `n` takes from a rotated rig.
    static func rotatedShare(_ n: P3, rig: String, rot: [Double]) -> Double? {
        guard let m = rotatedRigs[rig] else { return nil }
        let len = max(1e-9, (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot())
        var k = m.ambient
        for (v, strength) in m.lights {
            let vl = max(1e-9, (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot())
            let l = turned(P3(x: v.x / vl, y: v.y / vl, z: v.z / vl), lat: rot[0], lon: rot[1], rev: rot[2])
            let d = (n.x * l.x + n.y * l.y + n.z * l.z) / len
            // soft's pair is a straight line across the face (its two lights cancel to one without the clamp).
            k += strength * (rig == "soft" ? d : max(0, d))
        }
        return max(0, k)
    }

    static func lit(_ base: Color, _ n: P3, rig: Rig, turn: Double, material m: Material? = nil) -> Color {
        let len = max(1e-9, (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot())
        let lean = min(1, abs(n.z) / len)
        let w = (1 - lean * lean).squareRoot()
        var k = [rig.front.0, rig.front.1, rig.front.2]
        // The back of the solid takes no light: the darkest of the walls (it
        // is what shows through the hairline between two quads).
        if n.z < 0 { k = (0..<3).map { i in rig.walls.map { [$0.0, $0.1, $0.2][i] }.min() ?? 0 } }
        var spec = 0.0
        if w > 1e-6 {
            let a = (atan2(n.y, n.x) * 180 / .pi - turn) * .pi / 180
            func at(_ pick: ((Double, Double, Double, Double)) -> Double) -> Double {
                let v = rig.walls.map(pick)
                let c0 = (v[0] + v[1] + v[2] + v[3]) / 4, c1 = (v[0] - v[2]) / 2
                let s1 = (v[1] - v[3]) / 2, c2 = (v[0] - v[1] + v[2] - v[3]) / 4
                return max(0, c0 + c1 * cos(a) + s1 * sin(a) + c2 * cos(2 * a))
            }
            let wall = [at { $0.0 }, at { $0.1 }, at { $0.2 }]
            if m == nil { for i in 0..<3 { k[i] = w * wall[i] + (1 - w) * k[i] } }
            if let m {
                var d = a * 180 / .pi
                d = d.truncatingRemainder(dividingBy: 360); if d < 0 { d += 360 }
                let up = d - 90   // degrees above the horizontal of the turned frame
                let edge = d < 270 ? max(0, min(1, up / 4)) : 0
                let g = (up - m.centre) / m.sigma
                for i in 0..<3 { k[i] = w * m.diffuse + (1 - w) * k[i] }
                spec = w * (m.floor + m.lobe * edge * exp(-0.5 * g * g))
            }
            // The fourth number is the white a highlight added where Lab A sampled
            // the wall. It moves with the camera and the material, so laid whole over
            // a wall it overshoots (a cyan wall washed out in shape_rotation) and
            // left out it undershoots (isometricRightUp); half is what both decks
            // like. PROVISIONAL until the material model replaces it.
            if m == nil { spec = 0.5 * w * at { $0.3 } }
        }
        func ch(_ v: Int, _ f: Double) -> Int { max(0, min(255, Int((Double(v) * f + 255 * spec).rounded()))) }
        return Color(argb: base.alpha, ch(base.red, k[0]), ch(base.green, k[1]), ch(base.blue, k[2]))
    }

    static func read(_ spPr: XNode?, colors: ColorContext) -> Scene3D? {
        let sp3d = spPr?.first("a:sp3d")
        var s = Scene3D(depth: max(0, sp3d?["extrusionH"].flatMap(Double.init) ?? 0) / Pptx.emu)
        s.extrusionColor = sp3d?.first("a:extrusionClr").flatMap(colors.color(in:))
        s.wireframe = sp3d?["prstMaterial"] == "legacyWireframe"
        s.material = sp3d?["prstMaterial"] ?? ""
        if let camera = spPr?.first("a:scene3d")?.first("a:camera") {
            let name = camera["prst"] ?? ""
            s.perspective = name.hasPrefix("legacyPerspective")
            s.cameraName = name
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
            // The rig's own roll about the line of sight is the same as turning it
            // (Lab A: rev 90 prints as dir="r", pixel for pixel). Its latitude and
            // longitude tip the lights out of the plane; not drawn yet.
            if let rev = rig.first("a:rot")?["rev"].flatMap(Double.init) { s.rigTurn += rev / 60000 }
            if let rot = rig.first("a:rot") {
                func deg(_ a: String) -> Double { (rot[a].flatMap(Double.init) ?? 0) / 60000 }
                s.rigRot = [deg("lat"), deg("lon"), deg("rev")]
            }
        }
        // Looked at square on, a solid is its own front.
        if s.oblique == nil, s.lat == 0, s.lon == 0, s.rev == 0 { return nil }
        return s
    }

    struct P3 { var x, y, z: Double }

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
    static func paint(_ shape: SlideShape, outline: Path, _ r: Rect, _ canvas: any Canvas, pxPerPt px: Double, onFront: (() -> Void)? = nil) -> Bool {
        guard let scene = shape.scene3d, !scene.isFlatTurn, let fill = shape.fill ?? shape.fillStyle?.stops.first?.color ?? shape.fillStyle?.color ?? (onFront != nil ? Color(0xFFFFFFFF) : nil) else { return false }
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
            if scene.oblique == nil, scene.cameraName.hasPrefix("perspective") {
                // The eye ~1100 pt away (swept on perspectiveContrastingLeft,
                // shape_rotation and cropped_image).
                let f = 1100 * px / (1100 * px - q.z)
                q.x *= f; q.y *= f
            }
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
            if let rot = scene.rigRot, let k = Extrusion.rotatedShare(n, rig: scene.rig, rot: rot) {
                func ch(_ v: Int) -> Int { max(0, min(255, Int((Double(v) * k).rounded()))) }
                return Color(argb: base.alpha, ch(base.red), ch(base.green), ch(base.blue))
            }
            if let table = Extrusion.rigs[scene.rig] { return Extrusion.lit(base, n, rig: table, turn: scene.rigTurn, material: scene.rig == "twoPt" && scene.rigTurn != 0 ? Extrusion.material(scene.material) : nil) }
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
        face(frontShows ? back : front, scene.legacy && (scene.perspective || n0.z < 0.9) ? lit(side, P3(x: -n0.x, y: -n0.y, z: -abs(n0.z))) : litLocal(side, P3(x: 0, y: 0, z: frontShows ? -1 : 1)), edge: nil)
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
                              scene.legacy && (scene.perspective || n0.z < 0.9) ? lit(side, n) : litLocal(side, local)))
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
        // A legacy camera that turns the face well away darkens it with the
        // tilt: twoPt at 60 degrees prints 0.39 of the fill (legacyCamera).
        let tilted = scene.legacy && n0.z > 0 && n0.z < 0.9
        let tiltK = (Extrusion.rigs[scene.rig]?.front.0 ?? 1) * pow(max(0, n0.z), 1.3)
        let shown = !frontShows ? (scene.rig == "twoPt" ? Color(argb: fill.alpha, Int(Double(fill.red) * Extrusion.material(scene.material).back), Int(Double(fill.green) * Extrusion.material(scene.material).back), Int(Double(fill.blue) * Extrusion.material(scene.material).back)) : dark(side)) : tilted ? Color(argb: fill.alpha, Int(Double(fill.red) * tiltK), Int(Double(fill.green) * tiltK), Int(Double(fill.blue) * tiltK)) : scene.legacy && scene.perspective ? bright(fill) : litLocal(fill, P3(x: 0, y: 0, z: 1))
        // Lab E: a legacy oblique camera's face carries a white sheen the rig
        // lights it with — the bottom-facing ones under threePt (.19, .24
        // when the camera is also turned), TopRight under twoPt (.18).
        var sheen = 0.0
        if scene.legacy, !scene.perspective, !tilted, frontShows {
            let nm = scene.cameraName
            if scene.rig == "threePt", nm.hasSuffix("Bottom") || nm.hasSuffix("BottomRight") { sheen = scene.rigRot != nil || scene.lat != 0 || scene.lon != 0 ? 0.24 : 0.19 }
            else if scene.rig == "twoPt", nm.hasSuffix("TopRight") { sheen = 0.18 }
        }
        var shownFace = shown
        if sheen > 0 {
            func lift(_ v: Int) -> Int { min(255, v + Int((255.0 * sheen).rounded())) }
            shownFace = Color(argb: shown.alpha, lift(shown.red), lift(shown.green), lift(shown.blue))
        }
        face(frontShows ? front : back, shownFace, edge: frontShows ? shape.outline : nil)
        if let onFront, frontShows {
            // The picture, carried onto the turned front: the frame's corners
            // say where its axes went.
            let tl = place(Offset(r.left, r.top), 0), tr = place(Offset(r.right, r.top), 0), bl = place(Offset(r.left, r.bottom), 0)
            let a = (tr.x - tl.x) / r.width, b = (tr.y - tl.y) / r.width, cc = (bl.x - tl.x) / r.height, d = (bl.y - tl.y) / r.height
            let e = c.dx + tl.x - a * r.left - cc * r.top, f = c.dy + tl.y - b * r.left - d * r.top
            canvas.save()
            let clip = Path()
            for ring in front { clip.addPolygon(ring.map(flat), true) }
            canvas.clipPath(clip)
            canvas.transform([a, b, 0, 0, cc, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1])
            onFront()
            canvas.restore()
        }
        return true
    }
}
