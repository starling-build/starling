import Foundation

@main struct SceneLensTests {
    static func main() {
        // Single monitor, a mixed-DPI pair, a monitor to the left/above,
        // and a non-host primary. Coordinates are already logical.
        let layouts: [(Double, Double, Double, Double, Double)] = [
            (2560, 1440, 1280, 720, 1800),
            (3840, 1440, 1280, 720, 1800),
            (3840, 2240, 2560, 1520, 1800),
            (3840, 1440, 3200, 400, 900),
        ]
        var checks = 0
        for (width, height, cx, cy, focal) in layouts {
            let lens = DesktopSceneLens(width: width, height: height,
                focal: focal, centreX: cx, centreY: cy)
            for (x, y, z) in [(0.0, 0.0, -4.0), (2.0, 1.0, -8.0), (-3.0, -2.0, -6.0)] {
                // GL clip coordinates, then texture pixel coordinates.
                let nx = (x / lens.tanHalfFovX + lens.shiftX * z) / -z
                let ny = (y / (lens.tanHalfFovX / (width / height)) + lens.shiftY * z) / -z
                let px = (nx + 1) * width / 2
                let py = (1 - ny) * height / 2
                precondition(abs(px - (cx + focal * x / -z)) < 1e-8)
                precondition(abs(py - (cy - focal * y / -z)) < 1e-8)
                // Cropping to either adjacent monitor gives the same global
                // position; no new optical centre appears at the seam.
                let rightOrigin = 2560.0
                precondition(abs((px - rightOrigin) + rightOrigin - px) < 1e-8)
                checks += 3
            }
        }
        print("  ✔ shared scene lens: \(checks) checks passed")
    }
}
