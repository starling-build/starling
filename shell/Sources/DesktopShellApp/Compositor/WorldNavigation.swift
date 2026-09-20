// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Optional walking corridor exported alongside a world. Bounds already include
/// body clearance. Surface rectangles come from the generated pavement geometry.
struct WorldNavigation: Decodable {
    let version: Int
    let areas: [[Double]]
    let obstacles: [[Double]]
    let surfaces: [[Double]]
    let spawn: [Double] // x, z, yaw degrees, pitch degrees
    let eye_height: Double

    static func load(_ path: String) -> WorldNavigation? {
        guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let nav = try? JSONDecoder().decode(Self.self, from: bytes), nav.valid else { return nil }
        return nav
    }

    var valid: Bool {
        func rows(_ values: [[Double]], _ count: Int) -> Bool {
            values.allSatisfy { $0.count == count && $0.allSatisfy(\.isFinite) }
        }
        guard version == 1, !areas.isEmpty, !surfaces.isEmpty,
              rows(areas, 4), rows(obstacles, 3), rows(surfaces, 5),
              spawn.count == 4, spawn.allSatisfy(\.isFinite),
              eye_height.isFinite, eye_height > 0,
              areas.allSatisfy({ $0[0] < $0[1] && $0[2] < $0[3] }),
              surfaces.allSatisfy({ $0[0] < $0[1] && $0[2] < $0[3] }),
              obstacles.allSatisfy({ $0[2] > 0 }) else { return false }
        return allows(spawn[0], spawn[1])
    }

    func ground(_ x: Double, _ z: Double) -> Double? {
        surfaces.lazy.filter { $0[0] <= x && x <= $0[1] && $0[2] <= z && z <= $0[3] }
            .map { $0[4] }.max()
    }

    func allows(_ x: Double, _ z: Double) -> Bool {
        x.isFinite && z.isFinite &&
        areas.contains { $0[0] <= x && x <= $0[1] && $0[2] <= z && z <= $0[3] } &&
        obstacles.allSatisfy { hypot(x - $0[0], z - $0[1]) >= $0[2] } && ground(x,z) != nil
    }

    /// Sweep in small steps, sliding along an edge instead of crossing it.
    /// Cap unexpected input deltas to avoid tunnelling or unbounded loops.
    func move(x: Double, z: Double, dx: Double, dz: Double) -> (x: Double, z: Double) {
        guard [x,z,dx,dz].allSatisfy(\.isFinite) else { return (x,z) }
        var dx = dx, dz = dz
        var length = hypot(dx,dz)
        if length > 1 { dx /= length; dz /= length; length = 1 }
        let steps = max(1, Int(ceil(length / 0.04)))
        var x = x, z = z
        for _ in 0..<steps {
            if allows(x + dx / Double(steps), z) { x += dx / Double(steps) }
            if allows(x, z + dz / Double(steps)) { z += dz / Double(steps) }
        }
        return (x,z)
    }
}
